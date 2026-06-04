package com.faster.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

@Service
public class FileStorageService {

    @Value("${app.upload.dir}")
    private String uploadDir;

    // ─── Save image and return its public URL ─────────
    public String saveImage(MultipartFile file,
                            String subFolder) {

        // Validate file is an image
        String contentType = file.getContentType();
        if (contentType == null ||
            !contentType.startsWith("image/")) {
            throw new RuntimeException(
                "Only image files are allowed");
        }

        // Validate file size (max 5MB)
        if (file.getSize() > 5 * 1024 * 1024) {
            throw new RuntimeException(
                "Image size must be less than 5MB");
        }

        try {
            // Generate unique filename
            String extension = getExtension(
                file.getOriginalFilename());
            String fileName = UUID.randomUUID()
                    .toString() + "." + extension;

            // Build the full path
            Path targetPath = Paths.get(
                uploadDir, subFolder, fileName);

            // Save file to disk
            Files.copy(file.getInputStream(),
                       targetPath,
                       StandardCopyOption.REPLACE_EXISTING);

            // Return public URL path
            return "/" + uploadDir + "/"
                   + subFolder + "/" + fileName;

        } catch (IOException e) {
            throw new RuntimeException(
                "Failed to save image: " + e.getMessage());
        }
    }

    // ─── Delete old image when replaced ──────────────
    public void deleteImage(String imageUrl) {
        if (imageUrl == null || imageUrl.isBlank()) return;
        try {
            // Remove leading slash
            Path filePath = Paths.get(
                imageUrl.startsWith("/")
                ? imageUrl.substring(1)
                : imageUrl);
            Files.deleteIfExists(filePath);
        } catch (IOException e) {
            // Log but don't crash if delete fails
            System.err.println(
                "Could not delete image: " + imageUrl);
        }
    }

    // ─── Extract file extension ───────────────────────
    private String getExtension(String filename) {
        if (filename == null ||
            !filename.contains(".")) {
            return "jpg";
        }
        return filename.substring(
            filename.lastIndexOf(".") + 1)
            .toLowerCase();
    }
}