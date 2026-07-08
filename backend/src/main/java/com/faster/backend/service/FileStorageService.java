package com.faster.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Set;
import java.util.UUID;

/**
 * Stores uploaded images.
 *
 * FIXES:
 *  - (HIGH) Extension is now validated against an allow-list. Previously any
 *    extension from the client filename was trusted and appended to disk
 *    (e.g. "shell.jsp", "x.svg" with embedded script).
 *  - (MEDIUM) Content-type check kept, but a real magic-byte sniff is added so
 *    a text/script file renamed .jpg with a spoofed Content-Type is rejected.
 *  - (MEDIUM) deleteImage() now resolves and confirms the path stays inside the
 *    upload root, preventing "../" traversal deletes.
 *  - subFolder is validated against a fixed set.
 */
@Service
public class FileStorageService {

    @Value("${app.upload.dir}")
    private String uploadDir;

    private static final Set<String> ALLOWED_EXT =
            Set.of("jpg", "jpeg", "png", "gif", "webp");

    private static final Set<String> ALLOWED_SUBFOLDERS =
            Set.of("items", "offers");

    private static final long MAX_BYTES = 5L * 1024 * 1024;

    public String saveImage(MultipartFile file, String subFolder) {

        if (!ALLOWED_SUBFOLDERS.contains(subFolder)) {
            throw new IllegalArgumentException("Invalid upload folder");
        }
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("No file provided");
        }

        String contentType = file.getContentType();
        if (contentType == null || !contentType.startsWith("image/")) {
            throw new IllegalArgumentException("Only image files are allowed");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new IllegalArgumentException("Image size must be less than 5MB");
        }

        String extension = getSafeExtension(file.getOriginalFilename());

        try {
            byte[] head = readHead(file);
            if (!looksLikeImage(head)) {
                throw new IllegalArgumentException("File content is not a valid image");
            }

            Path root = Paths.get(uploadDir).toAbsolutePath().normalize();
            Path targetDir = root.resolve(subFolder).normalize();
            Files.createDirectories(targetDir);

            String fileName = UUID.randomUUID() + "." + extension;
            Path targetPath = targetDir.resolve(fileName).normalize();

            // Defense in depth: ensure we never escape the upload root
            if (!targetPath.startsWith(root)) {
                throw new IllegalArgumentException("Invalid target path");
            }

            Files.copy(file.getInputStream(), targetPath,
                    StandardCopyOption.REPLACE_EXISTING);

            return "/" + uploadDir + "/" + subFolder + "/" + fileName;

        } catch (IOException e) {
            throw new RuntimeException("Failed to save image");
        }
    }

    public void deleteImage(String imageUrl) {
        if (imageUrl == null || imageUrl.isBlank()) return;
        try {
            Path root = Paths.get(uploadDir).toAbsolutePath().normalize();
            String relative = imageUrl.startsWith("/") ? imageUrl.substring(1) : imageUrl;
            Path filePath = Paths.get(relative).toAbsolutePath().normalize();

            // Only delete if the resolved path is genuinely inside the upload root
            if (!filePath.startsWith(root)) {
                System.err.println("Refusing to delete path outside upload root: " + imageUrl);
                return;
            }
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            System.err.println("Could not delete image: " + imageUrl);
        }
    }

    private String getSafeExtension(String filename) {
        if (filename == null || !filename.contains(".")) {
            return "jpg";
        }
        String ext = filename.substring(filename.lastIndexOf(".") + 1)
                .toLowerCase().replaceAll("[^a-z0-9]", "");
        if (!ALLOWED_EXT.contains(ext)) {
            throw new IllegalArgumentException(
                    "Unsupported image type. Allowed: " + ALLOWED_EXT);
        }
        return ext;
    }

    private byte[] readHead(MultipartFile file) throws IOException {
        byte[] head = new byte[12];
        try (var in = file.getInputStream()) {
            int read = in.read(head);
            if (read < 0) return new byte[0];
        }
        return head;
    }

    /** Minimal magic-byte sniff for JPEG / PNG / GIF / WEBP. */
    private boolean looksLikeImage(byte[] b) {
        if (b.length < 4) return false;
        // JPEG FF D8 FF
        if ((b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return true;
        // PNG 89 50 4E 47
        if ((b[0] & 0xFF) == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
        // GIF 'G' 'I' 'F'
        if (b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return true;
        // WEBP 'R' 'I' 'F' 'F' .... 'W' 'E' 'B' 'P'
        if (b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
                && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') return true;
        return false;
    }
}
