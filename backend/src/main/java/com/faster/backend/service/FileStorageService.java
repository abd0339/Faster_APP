package com.faster.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.MalformedURLException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Set;
import java.util.UUID;

/**
 * Stores uploaded images.
 *
 * Two completely separate storage roots:
 *
 *  1. PUBLIC  (app.upload.dir) — item photos, offer banners.
 *     Served directly by nginx at /uploads/**, world-readable
 *     by design. Untouched by this change.
 *
 *  2. PRIVATE (app.private-upload.dir) — driver documents
 *     (profile photo, national ID, license front/back).
 *     NEW. This directory is NOT mounted into the nginx
 *     container and has NO nginx location block at all —
 *     it is physically unreachable from the internet. The
 *     only way to read these bytes is through the
 *     authenticated Spring endpoints in DriverController /
 *     AdminController, which check the JWT + role before
 *     calling loadPrivateImage() below. This is the fix for
 *     the PII exposure risk flagged when adding driver
 *     document uploads — see Faster_Logistics_File_Storage_Architecture.md.
 */
@Service
public class FileStorageService {

    @Value("${app.upload.dir}")
    private String uploadDir;

    @Value("${app.private-upload.dir}")
    private String privateUploadDir;

    private static final Set<String> ALLOWED_EXT =
            Set.of("jpg", "jpeg", "png", "gif", "webp");

    private static final Set<String> ALLOWED_SUBFOLDERS =
            Set.of("items", "offers");

    // Only "drivers" exists today. Kept as an explicit
    // allow-list (not a free-form path) so a future caller
    // can never pass an arbitrary subFolder string through
    // to disk.
    private static final Set<String> ALLOWED_PRIVATE_SUBFOLDERS =
            Set.of("drivers");

    private static final long MAX_BYTES = 5L * 1024 * 1024;

    // ═════════════════════════════════════════════════
    // PUBLIC STORAGE — unchanged from before
    // ═════════════════════════════════════════════════

    public String saveImage(MultipartFile file, String subFolder) {

        if (!ALLOWED_SUBFOLDERS.contains(subFolder)) {
            throw new IllegalArgumentException("Invalid upload folder");
        }
        validateImage(file);

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

            if (!filePath.startsWith(root)) {
                System.err.println("Refusing to delete path outside upload root: " + imageUrl);
                return;
            }
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            System.err.println("Could not delete image: " + imageUrl);
        }
    }

    // ═════════════════════════════════════════════════
    // PRIVATE STORAGE — driver documents (NEW)
    // ═════════════════════════════════════════════════

    /**
     * Saves a private document (driver photo, national ID,
     * license front/back). Returns a RELATIVE path — never
     * a public URL — meant to be stored in the User entity
     * and later resolved only via loadPrivateImage().
     *
     * @param entityId used to namespace the folder, e.g.
     *                 "drivers/{entityId}/..." — matches the
     *                 storage layout in the architecture doc.
     */
    public String savePrivateImage(MultipartFile file, String subFolder, Long entityId) {

        if (!ALLOWED_PRIVATE_SUBFOLDERS.contains(subFolder)) {
            throw new IllegalArgumentException("Invalid private upload folder");
        }
        if (entityId == null) {
            throw new IllegalArgumentException("entityId is required");
        }
        validateImage(file);

        String extension = getSafeExtension(file.getOriginalFilename());

        try {
            byte[] head = readHead(file);
            if (!looksLikeImage(head)) {
                throw new IllegalArgumentException("File content is not a valid image");
            }

            Path root = Paths.get(privateUploadDir).toAbsolutePath().normalize();
            Path targetDir = root.resolve(subFolder)
                    .resolve(String.valueOf(entityId))
                    .normalize();
            Files.createDirectories(targetDir);

            String fileName = UUID.randomUUID() + "." + extension;
            Path targetPath = targetDir.resolve(fileName).normalize();

            if (!targetPath.startsWith(root)) {
                throw new IllegalArgumentException("Invalid target path");
            }

            Files.copy(file.getInputStream(), targetPath,
                    StandardCopyOption.REPLACE_EXISTING);

            // Relative path stored in DB — NOT servable by nginx,
            // only resolvable through loadPrivateImage() below.
            return subFolder + "/" + entityId + "/" + fileName;

        } catch (IOException e) {
            throw new RuntimeException("Failed to save document");
        }
    }

    /**
     * Loads a private document for streaming back through an
     * authenticated controller endpoint. The caller (controller)
     * is responsible for checking the requester is either the
     * document owner (driver viewing their own doc) or an ADMIN
     * before calling this — this method only guarantees the
     * resolved path cannot escape the private root.
     */
    public Resource loadPrivateImage(String relativePath) {
        if (relativePath == null || relativePath.isBlank()) {
            throw new IllegalArgumentException("Document not found");
        }
        try {
            Path root = Paths.get(privateUploadDir).toAbsolutePath().normalize();
            Path filePath = root.resolve(relativePath).normalize();

            // Defense in depth: never resolve outside the private root
            if (!filePath.startsWith(root)) {
                throw new IllegalArgumentException("Invalid document path");
            }
            if (!Files.exists(filePath)) {
                throw new IllegalArgumentException("Document not found");
            }

            Resource resource = new UrlResource(filePath.toUri());
            if (!resource.exists() || !resource.isReadable()) {
                throw new IllegalArgumentException("Document not found");
            }
            return resource;

        } catch (MalformedURLException e) {
            throw new IllegalArgumentException("Document not found");
        }
    }

    public void deletePrivateImage(String relativePath) {
        if (relativePath == null || relativePath.isBlank()) return;
        try {
            Path root = Paths.get(privateUploadDir).toAbsolutePath().normalize();
            Path filePath = root.resolve(relativePath).normalize();

            if (!filePath.startsWith(root)) {
                System.err.println("Refusing to delete path outside private root: " + relativePath);
                return;
            }
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            System.err.println("Could not delete private document: " + relativePath);
        }
    }

    // ═════════════════════════════════════════════════
    // SHARED HELPERS
    // ═════════════════════════════════════════════════

    private void validateImage(MultipartFile file) {
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
        if ((b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) return true;
        if ((b[0] & 0xFF) == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return true;
        if (b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return true;
        if (b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
                && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') return true;
        return false;
    }
}