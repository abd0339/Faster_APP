package com.faster.backend.config;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@Configuration
public class FileStorageConfig implements WebMvcConfigurer {

    @Value("${app.upload.dir}")
    private String uploadDir;

    // ─── Create upload folders on startup ────────────
    @PostConstruct
    public void init() {
        try {
            createDir(uploadDir);
            createDir(uploadDir + "/items");
            createDir(uploadDir + "/offers");
        } catch (IOException e) {
            throw new RuntimeException(
                "Could not create upload directories: "
                + e.getMessage());
        }
    }

    // ─── Serve /uploads/** as static files ───────────
    // This makes http://localhost:8080/uploads/items/abc.jpg
    // return the actual file from disk
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        String absolutePath = Paths.get(uploadDir)
                .toAbsolutePath().toString();

        registry
            .addResourceHandler("/uploads/**")
            .addResourceLocations("file:" + absolutePath + "/");
    }

    private void createDir(String path) throws IOException {
        Path p = Paths.get(path);
        if (!Files.exists(p)) {
            Files.createDirectories(p);
        }
    }

    public String getUploadDir() {
        return uploadDir;
    }
}