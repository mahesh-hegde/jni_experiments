// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:ffigen/src/code_generator.dart';

import 'binding_string.dart';
import 'utils.dart';
import 'writer.dart';

const _vtableClasses = {
  "JNINativeInterface": "JniEnv",
  "JNIInvokeInterface": "JavaVM"
};

const methodNameRenames = {"throw": "throwException" };

enum CompoundType { struct, union }

/// A binding for Compound type - Struct/Union.
abstract class Compound extends BindingType {
  /// Marker for if a struct definition is complete.
  ///
  /// A function can be safely pass this struct by value if it's complete.
  bool isIncomplete;

  List<Member> members;

  bool get isOpaque => members.isEmpty;

  /// Value for `@Packed(X)` annotation. Can be null (no packing), 1, 2, 4, 8,
  /// or 16.
  ///
  /// Only supported for [CompoundType.struct].
  int? pack;

  /// Marker for checking if the dependencies are parsed.
  bool parsedDependencies = false;

  CompoundType compoundType;
  bool get isStruct => compoundType == CompoundType.struct;
  bool get isUnion => compoundType == CompoundType.union;

  Compound({
    String? usr,
    String? originalName,
    required String name,
    required this.compoundType,
    this.isIncomplete = false,
    this.pack,
    String? dartDoc,
    List<Member>? members,
    bool isInternal = false,
  })  : members = members ?? [],
        super(
          usr: usr,
          originalName: originalName,
          name: name,
          dartDoc: dartDoc,
          isInternal: isInternal,
        );

  factory Compound.fromType({
    required CompoundType type,
    String? usr,
    String? originalName,
    required String name,
    bool isIncomplete = false,
    int? pack,
    String? dartDoc,
    List<Member>? members,
  }) {
    switch (type) {
      case CompoundType.struct:
        return Struct(
          usr: usr,
          originalName: originalName,
          name: name,
          isIncomplete: isIncomplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
        );
      case CompoundType.union:
        return Union(
          usr: usr,
          originalName: originalName,
          name: name,
          isIncomplete: isIncomplete,
          pack: pack,
          dartDoc: dartDoc,
          members: members,
        );
    }
  }

  List<int> _getArrayDimensionLengths(Type type) {
    final array = <int>[];
    var startType = type;
    while (startType is ConstantArray) {
      array.add(startType.length);
      startType = startType.child;
    }
    return array;
  }

  String _getInlineArrayTypeString(Type type, Writer w) {
    if (type is ConstantArray) {
      return '${w.ffiLibraryPrefix}.Array<'
          '${_getInlineArrayTypeString(type.child, w)}>';
    }
    return type.getCType(w);
  }

  @override
  BindingString toBindingString(Writer w) {
    final s = StringBuffer();
    final es = StringBuffer();
    String ptrTypeString = "_"; // need this later
    final enclosingClassName = name;
    if (_vtableClasses.containsKey(enclosingClassName)) {
      final ffi = w.ffiLibraryPrefix;
      final ptrType = _vtableClasses[enclosingClassName]!;
      ptrTypeString = "$ffi.Pointer<$ptrType>";
      es.write(
          "extension ${enclosingClassName}Extension on $ptrTypeString {\n");
    }
    if (dartDoc != null) {
      s.write(makeDartDoc(dartDoc!));
    }

    /// Adding [enclosingClassName] because dart doesn't allow class member
    /// to have the same name as the class.
    final localUniqueNamer = UniqueNamer({enclosingClassName});

    /// Marking type names because dart doesn't allow class member to have the
    /// same name as a type name used internally.
    for (final m in members) {
      localUniqueNamer.markUsed(m.type.getDartType(w));
    }

    /// Write @Packed(X) annotation if struct is packed.
    if (isStruct && pack != null) {
      s.write('@${w.ffiLibraryPrefix}.Packed($pack)\n');
    }
    final dartClassName = isStruct ? 'Struct' : 'Union';
    // Write class declaration.
    s.write('class $enclosingClassName extends ');
    s.write('${w.ffiLibraryPrefix}.${isOpaque ? 'Opaque' : dartClassName}{\n');
    const depth = '  ';
    for (final m in members) {
      m.name = localUniqueNamer.makeUnique(m.name);
      if (m.type is ConstantArray) {
        s.write('$depth@${w.ffiLibraryPrefix}.Array.multi(');
        s.write('${_getArrayDimensionLengths(m.type)})\n');
        s.write('${depth}external ${_getInlineArrayTypeString(m.type, w)} ');
        s.write('${m.name};\n\n');
      } else {
        if (m.dartDoc != null) {
          s.write(depth + '/// ');
          s.writeAll(m.dartDoc!.split('\n'), '\n' + depth + '/// ');
          s.write('\n');
        }
        if (!sameDartAndCType(m.type, w)) {
          s.write('$depth@${m.type.getCType(w)}()\n');
        }
        if (_vtableClasses.containsKey(enclosingClassName) &&
            m.type is PointerType &&
            (m.type as PointerType).child is NativeFunc) {
          final nf = (m.type as PointerType).child as NativeFunc;
          final f = nf.type as FunctionType;

		  if (m.name == "NewObjectV" || m.name.startsWith("Call") &&
              m.name.endsWith("MethodV")) {
          	s.write('${depth}external ${m.type.getDartType(w)} _${m.name};\n\n');
            continue;
          }

          s.write('${depth}external ${m.type.getDartType(w)} ${m.name};\n\n');
          final eParams = f.parameters.toList(); // copy
          final implicitThis = true;
          if (implicitThis) {
            eParams.removeAt(0);
          }
		  var methodName = m.name[0].toLowerCase() + m.name.substring(1);
		  if (methodNameRenames.containsKey(methodName)) {
			methodName = methodNameRenames[methodName]!;
		  }
          if (m.dartDoc != null) {
            es.write('$depth/// ');
            es.writeAll(m.dartDoc!.split('\n'), '\n$depth/// ');
            es.write('\n');
            es.write("$depth///\n"
                "$depth/// This is an automatically generated extension method\n");
          }
		  // replace [m.name] by [methodName] to lowercase
          es.write("$depth@pragma('vm:prefer-inline')\n"
              "$depth${f.returnType.getDartType(w)} ${m.name}(");
          final visibleParams = <String>[];
          final actualParams = <String>[if (implicitThis) "this"];
          final callableFnType = f.getDartType(w);

          for (int i = 0; i < eParams.length; i++) {
            final p = eParams[i];
            final paramName = p.name.isEmpty
                ? (m.params != null ? m.params![i + 1] : "arg$i")
                : p.name;
            visibleParams.add("${p.type.getDartType(w)} $paramName");
            actualParams.add(paramName);
          }

          es.write("${visibleParams.join(', ')}) {\n");
          es.write(
              "$depth${depth}return value.ref.${m.name}.asFunction<$callableFnType>()(");
          es.write(actualParams.join(", "));
          es.write(");\n$depth}\n\n");
        } else {
          s.write('${depth}external ${m.type.getDartType(w)} ${m.name};\n\n');
        }
      }
    }
    if (_vtableClasses.containsKey(enclosingClassName)) {
      es.write("}\n\n");
    }
    s.write('}\n\n');

    return BindingString(
        type: isStruct ? BindingStringType.struct : BindingStringType.union,
        string: s.toString() + es.toString());
  }

  @override
  void addDependencies(Set<Binding> dependencies) {
    if (dependencies.contains(this)) return;

    dependencies.add(this);
    for (final m in members) {
      m.type.addDependencies(dependencies);
    }
  }

  @override
  bool get isIncompleteCompound => isIncomplete;

  @override
  String getCType(Writer w) => name;
}

class Member {
  final String? dartDoc;
  final String originalName;
  String name;
  final Type type;
  final List<String>? params;

  Member({
    String? originalName,
    required this.name,
    required this.type,
    this.dartDoc,
    this.params,
  }) : originalName = originalName ?? name;
}
