package com.example.flutter_xlog_example

import android.os.Bundle
import com.gosh.flutter_xlog.XLogNative
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    XLogNative.i("ExampleNative", "Android log before Flutter xlog initialization")
    super.onCreate(savedInstanceState)
  }
}
