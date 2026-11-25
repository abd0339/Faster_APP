package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Full-codebase review cleanup round (2026-11) — saveImage/savePrivateImage
 * and deleteImage/deletePrivateImage were each duplicated independently;
 * now both pairs share storeValidatedImage/deleteStoredFile. These tests
 * cover the shared helpers through both public entry points to confirm
 * the refactor preserved behavior for each.
 */
class FileStorageServiceTest {

    private FileStorageService service;

    @TempDir
    Path tempDir;

    // Minimal valid PNG magic-byte header (looksLikeImage only reads 12
    // bytes), padded so file.getSize() reflects a real small file.
    private static final byte[] PNG_HEADER = {
            (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0
    };

    @BeforeEach
    void setUp() {
        service = new FileStorageService();
        ReflectionTestUtils.setField(service, "uploadDir",
                tempDir.resolve("uploads").toString());
        ReflectionTestUtils.setField(service, "privateUploadDir",
                tempDir.resolve("private-uploads").toString());
    }

    private MockMultipartFile pngFile() {
        return new MockMultipartFile(
                "file", "photo.png", "image/png", PNG_HEADER);
    }

    @Test
    void saveImage_savesUnderUploadDirAndReturnsPublicUrl() throws IOException {
        String url = service.saveImage(pngFile(), "items");

        assertTrue(url.startsWith("/"), "public URL should be absolute: " + url);
        assertTrue(url.contains("/items/"));
        assertTrue(url.endsWith(".png"));

        // The returned URL is "/<uploadDir>/items/<file>" — strip the
        // leading slash to get the path relative to the project root.
        Path saved = Path.of(url.substring(1));
        assertTrue(Files.exists(saved));
    }

    @Test
    void saveImage_rejectsDisallowedSubfolder() {
        assertThrows(IllegalArgumentException.class,
                () -> service.saveImage(pngFile(), "not-a-real-folder"));
    }

    @Test
    void saveImage_rejectsContentThatIsNotActuallyAnImage() {
        MockMultipartFile notAnImage = new MockMultipartFile(
                "file", "fake.png", "image/png", "not a real png".getBytes());

        assertThrows(IllegalArgumentException.class,
                () -> service.saveImage(notAnImage, "items"));
    }

    @Test
    void deleteImage_removesAFileSavedBySaveImage() {
        String url = service.saveImage(pngFile(), "items");
        Path saved = Path.of(url.substring(1));
        assertTrue(Files.exists(saved));

        service.deleteImage(url);

        assertFalse(Files.exists(saved));
    }

    @Test
    void deleteImage_withNullOrBlank_doesNothing() {
        assertDoesNotThrowOnNullOrBlankDelete();
    }

    private void assertDoesNotThrowOnNullOrBlankDelete() {
        service.deleteImage(null);
        service.deleteImage("");
        service.deleteImage("   ");
    }

    @Test
    void savePrivateImage_savesUnderPrivateUploadDirAndReturnsRelativePath() {
        String relativePath = service.savePrivateImage(pngFile(), "drivers", 42L);

        assertEquals(true, relativePath.startsWith("drivers/42/"));
        assertTrue(relativePath.endsWith(".png"));

        // Must NOT be a public URL (no leading slash, no uploadDir prefix).
        assertFalse(relativePath.startsWith("/"));
    }

    @Test
    void savePrivateImage_rejectsDisallowedSubfolder() {
        assertThrows(IllegalArgumentException.class,
                () -> service.savePrivateImage(pngFile(), "items", 1L));
    }

    @Test
    void savePrivateImage_requiresEntityId() {
        assertThrows(IllegalArgumentException.class,
                () -> service.savePrivateImage(pngFile(), "drivers", null));
    }

    @Test
    void loadPrivateImage_resolvesWhatSavePrivateImageReturned() {
        String relativePath = service.savePrivateImage(pngFile(), "drivers", 7L);

        assertTrue(service.loadPrivateImage(relativePath).exists());
    }

    @Test
    void loadPrivateImage_rejectsPathTraversalAttempt() {
        assertThrows(IllegalArgumentException.class,
                () -> service.loadPrivateImage("../../etc/passwd"));
    }

    @Test
    void deletePrivateImage_removesAFileSavedBySavePrivateImage() {
        String relativePath = service.savePrivateImage(pngFile(), "drivers", 9L);
        assertTrue(service.loadPrivateImage(relativePath).exists());

        service.deletePrivateImage(relativePath);

        assertThrows(IllegalArgumentException.class,
                () -> service.loadPrivateImage(relativePath));
    }

    @Test
    void bothSavePaths_rejectOversizedFiles() {
        byte[] big = new byte[6 * 1024 * 1024];
        System.arraycopy(PNG_HEADER, 0, big, 0, PNG_HEADER.length);
        MockMultipartFile tooBig = new MockMultipartFile(
                "file", "big.png", "image/png", big);

        assertThrows(IllegalArgumentException.class,
                () -> service.saveImage(tooBig, "items"));
        assertThrows(IllegalArgumentException.class,
                () -> service.savePrivateImage(tooBig, "drivers", 1L));
    }
}
