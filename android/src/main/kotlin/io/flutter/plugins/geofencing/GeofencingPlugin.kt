// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.geofencing

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.huawei.hms.location.Geofence as HMSGeofence
import com.huawei.hms.location.GeofenceService as HMSGeofenceService
import com.huawei.hms.location.LocationServices as HMSLocationServices
import com.huawei.hms.location.GeofenceRequest as HMSGeofenceRequest
import com.huawei.hmf.tasks.OnCompleteListener
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.PluginRegistry.Registrar
import org.json.JSONArray

class GeofencingPlugin : ActivityAware, FlutterPlugin, MethodCallHandler {
  private var mContext : Context? = null
  private var mActivity : Activity? = null
  private var mGeofencingClient : GeofencingClient? = null
  private var mHmsGeofenceSvc : HMSGeofenceService? = null

  val geofenceClientGMS: GeofencingClient get() = mGeofencingClient!!
  val geofenceClientHMS: HMSGeofenceService get() = mHmsGeofenceSvc!!

  companion object {
    @JvmStatic
    private val TAG = "GeofencingPlugin"
    @JvmStatic
    val SHARED_PREFERENCES_KEY = "geofencing_plugin_cache"
    @JvmStatic
    val CALLBACK_HANDLE_KEY = "callback_handle"
    @JvmStatic
    val CALLBACK_DISPATCHER_HANDLE_KEY = "callback_dispatch_handler"
    @JvmStatic
    val PERSISTENT_GEOFENCES_KEY = "persistent_geofences"
    @JvmStatic
    val PERSISTENT_GEOFENCES_IDS = "persistent_geofences_ids"
    @JvmStatic
    private val sGeofenceCacheLock = Object()

    @JvmStatic
    fun reRegisterAfterReboot(context: Context) {
      synchronized(sGeofenceCacheLock) {
        var p = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        var persistentGeofences = p.getStringSet(PERSISTENT_GEOFENCES_IDS, null)
        if (persistentGeofences == null) {
          return
        }
        for (id in persistentGeofences) {
          val gfJson = p.getString(getPersistentGeofenceKey(id), null)
          if (gfJson == null) {
            continue
          }
          val gfArgs = JSONArray(gfJson)
          val list = ArrayList<Object>()
          for (i in 0 until gfArgs.length()) {
            list.add(gfArgs.get(i) as Object)
          }
          registerGeofence(context, list, null, false)
        }
      }
    }

    @JvmStatic
    private fun registerGeofence(context: Context,
                                  args: ArrayList<*>?,
                                  result: Result?,
                                  cache: Boolean,
                                  thisPtr: GeofencingPlugin? = null) {
      val callbackHandle = args!![0] as Long
      val id = args[1] as String
      val lat = args[2] as Double
      val long = args[3] as Double
      val radius = (args[4] as Number).toFloat()
      val fenceTriggers = args[5] as Int
      val initialTriggers = args[6] as Int
      val expirationDuration = (args[7] as Int).toLong()
      val loiteringDelay = args[8] as Int
      val notificationResponsiveness = args[9] as Int

      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
              (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                      == PackageManager.PERMISSION_DENIED)) {
        val msg = "'registerGeofence' requires the ACCESS_FINE_LOCATION permission."
        Log.w(TAG, msg)
        result?.error(msg, null, null)
      }

      // try with GMS location service
      val geoFenceClient = if (thisPtr == null) LocationServices.getGeofencingClient(context) else thisPtr.geofenceClientGMS
      val geofence = Geofence.Builder()
                    .setRequestId(id)
                    .setCircularRegion(lat, long, radius)
                    .setTransitionTypes(fenceTriggers)
                    .setLoiteringDelay(loiteringDelay)
                    .setNotificationResponsiveness(notificationResponsiveness)
                    .setExpirationDuration(expirationDuration)
                    .build()
        geoFenceClient.addGeofences(getGeofencingRequest(geofence, initialTriggers),
              getGeofencePendingIntent(context, callbackHandle))?.run {
        addOnSuccessListener {
          Log.i(TAG, "Successfully added geofence")
          if (cache) {
            addGeofenceToCache(context, id, args)
          }
          result?.success(true)
        }
        addOnFailureListener {
          Log.e(TAG, "Failed to add geofence through GMS location service: $it, retry with HMS location service")
          val geoFenceClientHMS = if (thisPtr == null) HMSLocationServices.getGeofenceService(context) else thisPtr.geofenceClientHMS
          val geoFenceHMS = HMSGeofence.Builder()
                        .setUniqueId(id)
                        .setValidContinueTime(expirationDuration)
                        .setRoundArea(lat, long, radius)
                        .setConversions(fenceTriggers)
                        .setDwellDelayTime(loiteringDelay)
                        .setNotificationInterval(notificationResponsiveness)
                        .build();
          val builder = HMSGeofenceRequest.Builder();
          builder.setInitConversions(initialTriggers);
          builder.createGeofence(geoFenceHMS);
          geoFenceClientHMS.createGeofenceList(builder.build(), getGeofencePendingIntent(context, callbackHandle))
            .addOnCompleteListener(OnCompleteListener<Void?> { task ->
            if (task.isSuccessful()) {
              Log.i(TAG, "add geofence success！");
              if (cache) {
                addGeofenceToCache(context, id, args)
              }
              result?.success(true)
            } else {
              Log.e(TAG, "Failed to add geofence: ${task.exception}")
              result?.error(task.exception.toString(), null, null)
            }
          })
        }
      }
    }

    @JvmStatic
    private fun addGeofenceToCache(context: Context, id: String, args: ArrayList<*>) {
      synchronized(sGeofenceCacheLock) {
        var p = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        var obj = JSONArray(args)
        var persistentGeofences = p.getStringSet(PERSISTENT_GEOFENCES_IDS, null)
        if (persistentGeofences == null) {
          persistentGeofences = HashSet<String>()
        } else {
          persistentGeofences = HashSet<String>(persistentGeofences)
        }
        persistentGeofences.add(id)
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(PERSISTENT_GEOFENCES_IDS, persistentGeofences)
                .putString(getPersistentGeofenceKey(id), obj.toString())
                .apply()
      }
    }

    @JvmStatic
    private fun initializeService(context: Context, args: ArrayList<*>?) {
      Log.d(TAG, "Initializing GeofencingService")
      val callbackHandle = args!![0] as Long
      context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
              .edit()
              .putLong(CALLBACK_DISPATCHER_HANDLE_KEY, callbackHandle)
              .apply()
    }

    @JvmStatic
    private fun getGeofencingRequest(geofence: Geofence, initialTrigger: Int): GeofencingRequest {
      return GeofencingRequest.Builder().apply {
        setInitialTrigger(initialTrigger)
        addGeofence(geofence)
      }.build()
    }

    @JvmStatic
    private fun getGeofencePendingIntent(context: Context, callbackHandle: Long): PendingIntent {
      val intent = Intent(context, GeofencingBroadcastReceiver::class.java).putExtra(CALLBACK_HANDLE_KEY, callbackHandle)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
      } else {
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT)
      }
    }

    @JvmStatic
    private fun removeGeofence(context: Context,
                                args: ArrayList<*>?,
                                result: Result,
                                thisPtr: GeofencingPlugin? = null) {
      val ids = listOf(args!![0] as String)
      val geoFenceClient = if (thisPtr == null) LocationServices.getGeofencingClient(context) else thisPtr.geofenceClientGMS
      geoFenceClient.removeGeofences(ids).run {
        addOnSuccessListener {
          for (id in ids) {
            removeGeofenceFromCache(context, id)
          }
          result.success(true)
        }
        addOnFailureListener {
          Log.e(TAG, "Failed to remove geofence through GMS location service: $it, retry with HMS location service")
          val geoFenceClientHMS = if (thisPtr == null) HMSLocationServices.getGeofenceService(context) else thisPtr.geofenceClientHMS
          geoFenceClientHMS.deleteGeofenceList(ids).addOnCompleteListener(OnCompleteListener<Void?> { task ->
            if (task.isSuccessful()) {
              Log.i(TAG, "remove geofence success！");
              for (id in ids) {
                removeGeofenceFromCache(context, id)
              }
              result?.success(true)
            } else {
              Log.e(TAG, "Failed to remove geofence: ${task.exception}")
              result?.error(task.exception.toString(), null, null)
            }
          })
        }
      }
    }

    @JvmStatic
    private fun getRegisteredGeofenceIds(context: Context, result: Result) {
      synchronized(sGeofenceCacheLock) {
        val list = ArrayList<String>()
        var p = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        var persistentGeofences = p.getStringSet(PERSISTENT_GEOFENCES_IDS, null)
        if (persistentGeofences != null && persistentGeofences.size > 0) {
          for (id in persistentGeofences) {
            list.add(id)
          }
        }
        result.success(list)
      }
    }

    @JvmStatic
    private fun removeGeofenceFromCache(context: Context, id: String) {
      synchronized(sGeofenceCacheLock) {
        var p = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        var persistentGeofences = p.getStringSet(PERSISTENT_GEOFENCES_IDS, null)
        if (persistentGeofences == null) {
          return
        }
        persistentGeofences = HashSet<String>(persistentGeofences)
        persistentGeofences.remove(id)
        p.edit()
                .remove(getPersistentGeofenceKey(id))
                .putStringSet(PERSISTENT_GEOFENCES_IDS, persistentGeofences)
                .apply()
      }
    }

    @JvmStatic
    private fun getPersistentGeofenceKey(id: String): String {
      return "persistent_geofence/" + id
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    mContext = binding.getApplicationContext()
    mGeofencingClient = LocationServices.getGeofencingClient(mContext!!)
    mHmsGeofenceSvc = HMSLocationServices.getGeofenceService(mContext!!)
    val channel = MethodChannel(binding.getBinaryMessenger(), "plugins.flutter.io/geofencing_plugin")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    mContext = null
    mGeofencingClient = null
    mHmsGeofenceSvc = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    mActivity = binding.getActivity()
  }

  override fun onDetachedFromActivity() {
    mActivity = null
  }

  override fun onDetachedFromActivityForConfigChanges() {
    mActivity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    mActivity = binding.getActivity()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    val args = call.arguments<ArrayList<*>>()
    when(call.method) {
      "GeofencingPlugin.initializeService" -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          mActivity?.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_BACKGROUND_LOCATION), 12312)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          mActivity?.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), 12312)
        }
        initializeService(mContext!!, args)
        result.success(true)
      }
      "GeofencingPlugin.registerGeofence" -> registerGeofence(mContext!!,
              args,
              result,
              true)
      "GeofencingPlugin.removeGeofence" -> removeGeofence(mContext!!,
              args,
              result)
      "GeofencingPlugin.getRegisteredGeofenceIds" -> getRegisteredGeofenceIds(mContext!!, result)
      else -> result.notImplemented()
    }
  }
}
