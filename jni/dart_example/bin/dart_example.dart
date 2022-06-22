import 'package:jni/jni.dart';

import 'dart:io';
import 'package:path/path.dart';

// This example shows how to use an external Java JAR using classpath
// on dart standalone / flutter desktop. This tool prints the text in PDF
// file to standard output using PDFBox library.
//
// This is only meant to demonstrate the usage of package:jni's utility API
// A better way to do this will be code generation, which is main part of this
// project.
// The utility library is still useful for one-off uses and debugging.

// For this to work
// * Download PDFBox, FontBox, and commons logging JARs from APACHE site
// * build libdartjni.so in src/ directory of package:jni, and move it to bin/

void writeText(String file) {
  var jni = Jni.getInstance();

  // var pdfTextStripper = new PDFTextStripper()
  var pdfTextStripper =
      jni.newInstance("org/apache/pdfbox/text/PDFTextStripper", "()V", []);

  // var inputFile = new FileInputStream(file)
  var inputFile = jni
      .newInstance("java/io/FileInputStream", "(Ljava/lang/String;)V", [file]);

  // pdDoc = PDDocument.load(inputFile)
  var pdDoc = jni.invokeObjectMethod(
      "org/apache/pdfbox/pdmodel/PDDocument",
      "load",
      "(Ljava/io/InputStream;)Lorg/apache/pdfbox/pdmodel/PDDocument;",
      [inputFile]);

  // var out = new OutputStreamWriter(System.out)
  var out = jni.retrieveObjectField(
      "java/lang/System", "out", "Ljava/io/PrintStream;");
  var outWriter = jni.newInstance("java/io/OutputStreamWriter", "(Ljava/io/OutputStream;)V", [out]);

  // pdfTextStripper.writeText(pdDoc, out)

  // Always pay close attention to signatures. It's the most error prone part.
  // If you get a method not found error, it's almost certainly related to signature.
  pdfTextStripper.callVoidMethodByName(
      "writeText",
      "(Lorg/apache/pdfbox/pdmodel/PDDocument;Ljava/io/Writer;)V",
      [pdDoc, outWriter]);

  // out.close()
  outWriter.callVoidMethodByName("close", "()V", []);

  // delete local objects
  for (var i in [inputFile, outWriter, out, pdDoc, pdfTextStripper]) {
    i.delete();
  }
}

void main(List<String> arguments) {
  final libPath =
      dirname(Platform.script.toFilePath(windows: Platform.isWindows));
  // download Apache pdfbox, fontbox and commons logging into jar/ folder using wget
  final pdfBoxJar = join(dirname(libPath), "jar", "pdfbox-2.0.26.jar");
  final fontBoxJar = join(dirname(libPath), "jar", "fontbox-2.0.26.jar");
  final commonsLoggingJar =
      join(dirname(libPath), "jar", "commons-logging-1.2.jar");

  Jni.spawn(
      helperDir: libPath,
      classPath: [pdfBoxJar, fontBoxJar, commonsLoggingJar]);

  writeText(arguments[0]);

  /*
  // Simple hello world.
  jni
      .retrieveObjectField("java/lang/System", "out", "Ljava/io/PrintStream;")
      .use((out) => out.callVoidMethodByName(
          "println", "(Ljava/lang/String;)V", ["Hello from JNI!"]));
  */
}
