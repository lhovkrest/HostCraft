import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Makes sure child processes (Java, Playit) can never outlive HostCraft on
/// Windows.
///
/// Every child is placed in one Job Object flagged KILL_ON_JOB_CLOSE. Windows
/// closes the job handle when HostCraft's process ends for any reason (normal
/// exit, crash, "End task" in Task Manager), which terminates everything in it.
/// On other platforms this does nothing: Android children die with the app's
/// process group and the foreground service is stopped explicitly.
class ProcessGuard {
  static int _job = 0;
  static bool _failed = false;

  static const _jobObjectExtendedLimitInformation = 9;
  static const _killOnJobClose = 0x2000;
  static const _processSetQuota = 0x0100;
  static const _processTerminate = 0x0001;

  /// Adds the process with [pid] to the kill-on-exit job. Never throws.
  static void adopt(int pid) {
    if (!Platform.isWindows || _failed) return;
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      if (_job == 0) {
        final create = k32.lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Utf16>),
          int Function(Pointer<Void>, Pointer<Utf16>)
        >('CreateJobObjectW');
        final setInfo = k32.lookupFunction<
          Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)
        >('SetInformationJobObject');
        final job = create(nullptr, nullptr);
        if (job == 0) throw StateError('CreateJobObject failed');
        // JOBOBJECT_EXTENDED_LIMIT_INFORMATION is 144 bytes on 64-bit Windows;
        // LimitFlags sits at byte offset 16.
        final info = calloc<Uint8>(144);
        try {
          info.cast<Uint32>()[4] = _killOnJobClose;
          final ok = setInfo(
            job,
            _jobObjectExtendedLimitInformation,
            info.cast<Void>(),
            144,
          );
          if (ok == 0) throw StateError('SetInformationJobObject failed');
        } finally {
          calloc.free(info);
        }
        _job = job; // Deliberately never closed: closing it kills the children.
      }
      final open = k32.lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');
      final assign = k32.lookupFunction<
        Int32 Function(IntPtr, IntPtr),
        int Function(int, int)
      >('AssignProcessToJobObject');
      final closeHandle = k32.lookupFunction<
        Int32 Function(IntPtr),
        int Function(int)
      >('CloseHandle');
      final handle = open(_processSetQuota | _processTerminate, 0, pid);
      if (handle == 0) return;
      assign(_job, handle);
      closeHandle(handle);
    } catch (_) {
      _failed = true; // Best effort; normal shutdown still kills the children.
    }
  }
}
