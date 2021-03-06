// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:ffigen/src/code_generator.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import '../test_utils.dart';

void main() {
  group('decl_decl_collision_test', () {
    setUpAll(() {
      logWarnings(Level.SEVERE);
    });
    test('declaration conflict', () {
      final l1 = Library(name: 'Bindings', bindings: [
        Struct(name: 'TestStruct'),
        Struct(name: 'TestStruct'),
        EnumClass(name: 'TestEnum'),
        EnumClass(name: 'TestEnum'),
        Func(
            name: 'testFunc', returnType: NativeType(SupportedNativeType.Void)),
        Func(
            name: 'testFunc', returnType: NativeType(SupportedNativeType.Void)),
        Constant(
          originalName: 'Test_Macro',
          name: 'Test_Macro',
          rawType: 'int',
          rawValue: '0',
        ),
        Constant(
          originalName: 'Test_Macro',
          name: 'Test_Macro',
          rawType: 'int',
          rawValue: '0',
        ),
        Typealias(
            name: 'testAlias', type: NativeType(SupportedNativeType.Void)),
        Typealias(
            name: 'testAlias', type: NativeType(SupportedNativeType.Void)),

        /// Conflicts across declarations.
        Struct(name: 'testCrossDecl'),
        Func(
            name: 'testCrossDecl',
            returnType: NativeType(SupportedNativeType.Void)),
        Constant(name: 'testCrossDecl', rawValue: '0', rawType: 'int'),
        EnumClass(name: 'testCrossDecl'),
        Typealias(
            name: 'testCrossDecl', type: NativeType(SupportedNativeType.Void)),

        /// Conflicts with ffi library prefix, name of prefix is changed.
        Struct(name: 'ffi'),
        Func(name: 'ffi1', returnType: NativeType(SupportedNativeType.Void)),
      ]);
      final l2 = Library(name: 'Bindings', bindings: [
        Struct(name: 'TestStruct'),
        Struct(name: 'TestStruct1'),
        EnumClass(name: 'TestEnum'),
        EnumClass(name: 'TestEnum1'),
        Func(
            name: 'testFunc',
            originalName: 'testFunc',
            returnType: NativeType(SupportedNativeType.Void)),
        Func(
            name: 'testFunc1',
            originalName: 'testFunc',
            returnType: NativeType(SupportedNativeType.Void)),
        Constant(
          originalName: 'Test_Macro',
          name: 'Test_Macro',
          rawType: 'int',
          rawValue: '0',
        ),
        Constant(
          originalName: 'Test_Macro',
          name: 'Test_Macro1',
          rawType: 'int',
          rawValue: '0',
        ),
        Typealias(
            name: 'testAlias', type: NativeType(SupportedNativeType.Void)),
        Typealias(
            name: 'testAlias1', type: NativeType(SupportedNativeType.Void)),
        Struct(name: 'testCrossDecl', originalName: 'testCrossDecl'),
        Func(
            name: 'testCrossDecl1',
            originalName: 'testCrossDecl',
            returnType: NativeType(SupportedNativeType.Void)),
        Constant(name: 'testCrossDecl2', rawValue: '0', rawType: 'int'),
        EnumClass(name: 'testCrossDecl3'),
        Typealias(
            name: 'testCrossDecl4', type: NativeType(SupportedNativeType.Void)),
        Struct(name: 'ffi'),
        Func(name: 'ffi1', returnType: NativeType(SupportedNativeType.Void)),
      ]);

      expect(l1.generate(), l2.generate());
    });
  });
}
