package com.faster.backend.config;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@Configuration
public class FileStorageConfig {

    @Value("${app.upload.dir}")
    private String uploadDir;

    // ─── Create upload folders on startup ────────────
    @PostConstruct
    public void init() {
        try {
            // Main uploads folder
            Path uploadPath = Paths.get(uploadDir);
            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }

            // Items images folder
            Path itemsPath = Paths.get(uploadDir + "/items");
            if (!Files.exists(itemsPath)) {
                Files.createDirectories(itemsPath);
            }

            // Offers images folder
            Path offersPath = Paths.get(uploadDir + "/offers");
            if (!Files.exists(offersPath)) {
                Files.createDirectories(offersPath);
            }

        } catch (IOException e) {
            throw new RuntimeException(
                "Could not create upload directories: "
                + e.getMessage());
        }
    }

    public String getUploadDir() {
        return uploadDir;
    }
}