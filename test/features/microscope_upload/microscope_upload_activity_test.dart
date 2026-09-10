import 'package:crystalapp/features/microscope_upload/models/microscope_file_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describes the exact role, bytes, and multipart position', () {
    const activity = MicroscopeUploadActivity(
      phase: MicroscopeUploadPhase.uploading,
      role: MicroscopeFileRole.tiff,
      completedBytes: 56 * 1024 * 1024,
      totalBytes: 83943688,
      currentPart: 7,
      totalParts: 11,
      savedParts: 6,
    );

    expect(activity.headline, 'Uploading TIFF');
    expect(activity.progress, closeTo(0.699, 0.01));
    expect(activity.detail, contains('56.0 MiB of 80.1 MiB'));
    expect(activity.detail, contains('part 7 of 11'));
    expect(activity.detail, contains('6 parts safely stored'));
  });

  test('explains automatic retry without losing completed work', () {
    const activity = MicroscopeUploadActivity(
      phase: MicroscopeUploadPhase.retrying,
      role: MicroscopeFileRole.tiff,
      completedBytes: 48 * 1024 * 1024,
      totalBytes: 83943688,
      currentPart: 7,
      totalParts: 11,
      savedParts: 6,
      retryNumber: 2,
      maxRetries: 3,
    );

    expect(activity.headline, 'Connection interrupted — retrying TIFF');
    expect(activity.detail, contains('Retry 2 of 3'));
    expect(activity.detail, contains('6 completed parts remain safely stored'));
  });

  test('distinguishes a bounded upload queue from analysis queueing', () {
    const waiting = MicroscopeUploadActivity(
      phase: MicroscopeUploadPhase.waiting,
    );
    const registered = MicroscopeUploadActivity(
      phase: MicroscopeUploadPhase.queued,
    );

    expect(waiting.headline, 'Queued for the next upload batch');
    expect(waiting.detail, contains('bounded batch'));
    expect(registered.headline, 'Image registered');
    expect(registered.detail, contains('queued for analysis'));
  });

  test('separates storage verification from image registration', () {
    expect(
      const MicroscopeUploadActivity(
        phase: MicroscopeUploadPhase.verifying,
        role: MicroscopeFileRole.tiff,
      ).headline,
      'Verifying TIFF in secure storage',
    );
    expect(
      const MicroscopeUploadActivity(
        phase: MicroscopeUploadPhase.registering,
      ).headline,
      'Registering the Image with the selected Bag',
    );
    expect(
      const MicroscopeUploadActivity(
        phase: MicroscopeUploadPhase.queued,
      ).detail,
      contains('queued for analysis'),
    );
  });
}
