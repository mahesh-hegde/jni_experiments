/// Run from templates directory

import 'dart:io' as io;
import 'package:path/path.dart';

var targetTypes = {
  "String": "String",
  "Object": "JniObject",
  "Boolean": "bool",
  "Byte": "int",
  "Char": "int",
  "Short": "int",
  "Int": "int",
  "Long": "int",
  "Float": "double",
  "Double": "double",
  "Void": "void"
};

var resultConverters = {
  "String": (String resultVar) => "final str = _env.asDartString($resultVar);"
		  "_env.DeleteLocalRef($resultVar);"
		  "return str",
  "Object": (String resultVar) => "return JniObject._(_env, $resultVar, nullptr)",
  "Boolean": (String resultVar) => "return $resultVar != 0",
};

var invokeResultConverters = {
  "String": (String resultVar) => "final str = env.asDartString($resultVar);"
		  "env.DeleteLocalRef($resultVar);"
		  "env.DeleteLocalRef(cls);"
		  "return str",
  "Object": (String resultVar) => "return JniObject._(env, $resultVar, cls)",
  "Boolean": (String resultVar) => "return $resultVar != 0",
};

void main(List<String> args) {
  final script = io.Platform.script;
  final scriptDir = dirname(script.toFilePath(windows: io.Platform.isWindows));
  final methodTemplates =
      io.File(join(scriptDir, 'JniObject_MethodCalls')).readAsStringSync();
  final fieldTemplates =
      io.File(join(scriptDir, 'JniObject_Fields')).readAsStringSync();
  final invokeTemplates =
      io.File(join(scriptDir, 'Invoke_Static_Methods')).readAsStringSync();
  final retrieveTemplates =
      io.File(join(scriptDir, 'Retrieve_Static_Fields')).readAsStringSync();

  var outputPath = join("lib", "src", "jni.dart");
  final outputFile = io.File(outputPath);
  var sInst = StringBuffer();
  var sStatic = StringBuffer();
  var sInvoke = StringBuffer();
  sInst.write("\n\n"
      "// AUTO GENERATED DO NOT EDIT\n"
      "// DELETE NEXT PART AND RE RUN GENERATOR AFTER CHANGING TEMPLATE\n\n"
      "\n"
      "extension JniObjectCallMethods on JniObject {");
  sStatic.write("\n\n"
      "extension JniClassCallMethods on JniClass {");
  sInvoke.write("\n\n"
      "extension JniInvokeMethods on Jni {");
  for (var t in targetTypes.keys) {
    void write(String template) {
      final resultConverter = resultConverters[t] ?? (resultVar) => "return $resultVar";
      final skel = template
          .replaceAll("{TYPE}", t == "String" ? "Object" : t)
		  .replaceAll("{PTYPE}", t)
          .replaceAll("{TARGET_TYPE}", targetTypes[t]!)
          .replaceAll("{RESULT}", resultConverter("result"));
      final inst_ =
          skel.replaceAll("{STATIC}", "").replaceAll("{THIS}", "_obj");
      final static_ =
          skel.replaceAll("{STATIC}", "Static").replaceAll("{THIS}", "_cls");
      sInst.write(inst_);
      sStatic.write(static_);
    }

    write(methodTemplates);
    if (t != "Void") {
      write(fieldTemplates);
    }
    var invokeResultConverter = (invokeResultConverters[t] ?? (String r) => "return $r");
    void writeI(String template) {
      final replaced = template
          .replaceAll("{TYPE}", t == "String" ? "Object" : t)
		  .replaceAll("{PTYPE}", t)
          .replaceAll("{TARGET_TYPE}", targetTypes[t]!)
          .replaceAll("{CLS_REF_DEL}",
              t == "Object" || t == "String" ? "" : "env.DeleteLocalRef(cls);\n")
          .replaceAll("{INVOKE_RESULT}", invokeResultConverter("result"));
      sInvoke.write(replaced);
    }
	writeI(invokeTemplates);
    if (t != "Void") {
		writeI(retrieveTemplates);
	}
  }
  sInst.write("}");
  sStatic.write("}");
  sInvoke.write("}");
  for (var s in [sInst, sStatic, sInvoke]) {
    outputFile.writeAsStringSync(s.toString(),
        mode: io.FileMode.append, flush: true);
  }
  io.Process.run("dart", ["format", outputPath]);
}
