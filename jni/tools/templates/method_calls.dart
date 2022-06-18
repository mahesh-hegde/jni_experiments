/// Run from templates directory

import 'dart:io' as io;
import 'package:path/path.dart';

var targetTypes = {
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
  "Object": (String resultVar) => "JniObject._(_env, $resultVar, nullptr)",
  "Boolean": (String resultVar) => "$resultVar != 0",
};

void main(List<String> args) {
  final script = io.Platform.script;
  final scriptDir = dirname(script.toFilePath(windows: io.Platform.isWindows));
  final templateFileMethods = io.File(join(scriptDir, 'JniObject_MethodCalls'));
  final methodTemplates = templateFileMethods.readAsStringSync();
  final templateFileFields = io.File(join(scriptDir, 'JniObject_Fields'));
  final fieldTemplates = templateFileFields.readAsStringSync();

  var outputPath = join("lib", "src", "jni.dart");
  final outputFile = io.File(outputPath);
  var sInst = StringBuffer();
  var sStatic = StringBuffer();
  sInst.write("\n\n"
      "// AUTO GENERATED DO NOT EDIT\n"
      "// DELETE NEXT PART AND RE RUN GENERATOR AFTER CHANGING TEMPLATE\n\n"
      "\n"
      "extension JniObjectCallMethods on JniObject {");
  sStatic.write("\n\n"
		  "extension JniClassCallMethods on JniClass {");
  for (var t in targetTypes.keys) {
    void write(String template) {
      final resultConverter = resultConverters[t] ?? (resultVar) => resultVar;
      final skel = template
          .replaceAll("{TYPE}", t)
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
  }
  sInst.write("}");
  sStatic.write("}");
  for (var s in [sInst, sStatic]) {
    outputFile.writeAsStringSync(s.toString(),
        mode: io.FileMode.append, flush: true);
  }
  io.Process.run("dart", ["format", outputPath]);
}
