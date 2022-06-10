package dev.dart.jni;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import android.util.Log;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

import android.content.Context;

@Keep
public class JniPlugin implements FlutterPlugin {
  
  @Override
  public void
  onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
	  setup(binding.getApplicationContext());
  }

  public static void registerWith(Registrar registrar) {
    JniPlugin plugin = new JniPlugin();
	plugin.setup(registrar.activeContext());
  }

  private void setup(Context context) {
	initializeJni(context, getClass().getClassLoader());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}

  native void initializeJni(Context context, ClassLoader classLoader);

  static {
	System.loadLibrary("dartjni");
  }
}

