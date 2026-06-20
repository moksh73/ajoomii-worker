import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';

/// Cloudinary upload service for Ajoomi Worker app.
/// All upload methods throw on failure so callers can catch and show UI errors.
class CloudinaryService {
  static const String _cloudName = 'doeswlkl3';
  static const String _uploadPreset = 'worker_upload';

  static final CloudinaryPublic _cloudinary = CloudinaryPublic(
    _cloudName,
    _uploadPreset,
    cache: false,
  );

  // ─────────────────────────────────────────
  // Upload a single image — THROWS on failure
  // Returns non-null secure URL on success
  // ─────────────────────────────────────────
  static Future<String> uploadImage(
    File imageFile, {
    String folder = 'worker_app',
  }) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imageFile.path,
          folder: folder,
          resourceType: CloudinaryResourceType.Image,
        ),
      );
      final url = response.secureUrl;
      if (url.isEmpty) throw Exception('Cloudinary returned empty URL');
      return url;
    } on CloudinaryException catch (e) {
      throw Exception('Cloudinary upload failed: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // Upload multiple images
  // Skips failed items; returns successful URLs only
  // ─────────────────────────────────────────
  static Future<List<String>> uploadMultipleImages(
    List<File> imageFiles, {
    String folder = 'worker_app',
  }) async {
    final List<String> uploadedUrls = [];
    for (final file in imageFiles) {
      try {
        final url = await uploadImage(file, folder: folder);
        uploadedUrls.add(url);
      } catch (_) {
        // continue with remaining files
      }
    }
    return uploadedUrls;
  }

  // ─────────────────────────────────────────
  // Upload profile picture with stable public_id
  // ─────────────────────────────────────────
  static Future<String> uploadProfilePicture(
    File imageFile,
    String userId,
  ) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imageFile.path,
          folder: 'worker_app/profiles',
          publicId: 'profile_$userId',
          resourceType: CloudinaryResourceType.Image,
        ),
      );
      final url = response.secureUrl;
      if (url.isEmpty) throw Exception('Cloudinary returned empty URL');
      return url;
    } on CloudinaryException catch (e) {
      throw Exception('Profile upload failed: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // Upload video
  // ─────────────────────────────────────────
  static Future<String> uploadVideo(
    File videoFile, {
    String folder = 'worker_app/videos',
  }) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          videoFile.path,
          folder: folder,
          resourceType: CloudinaryResourceType.Video,
        ),
      );
      final url = response.secureUrl;
      if (url.isEmpty) throw Exception('Cloudinary returned empty URL');
      return url;
    } on CloudinaryException catch (e) {
      throw Exception('Video upload failed: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // Upload from raw bytes (e.g. web picker)
  // ─────────────────────────────────────────
  static Future<String> uploadFromBytes(
    List<int> bytes,
    String fileName, {
    String folder = 'worker_app',
  }) async {
    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          bytes,
          identifier: fileName,
          folder: folder,
          resourceType: CloudinaryResourceType.Image,
        ),
      );
      final url = response.secureUrl;
      if (url.isEmpty) throw Exception('Cloudinary returned empty URL');
      return url;
    } on CloudinaryException catch (e) {
      throw Exception('Bytes upload failed: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // URL transformations (no network call)
  // ─────────────────────────────────────────
  static String getOptimizedUrl(
    String originalUrl, {
    int width = 400,
    int height = 400,
    String crop = 'fill',
    String quality = 'auto',
    String format = 'auto',
  }) {
    return originalUrl.replaceFirst(
      '/upload/',
      '/upload/w_$width,h_$height,c_$crop,q_$quality,f_$format/',
    );
  }

  static String getThumbnailUrl(String originalUrl, {int size = 150}) {
    return getOptimizedUrl(originalUrl, width: size, height: size);
  }
}
