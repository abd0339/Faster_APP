package com.faster.backend.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    // ─── Validation errors (@Valid on DTOs) ──────────
    // Returns 400 with a map of field → error message
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidationErrors(
            MethodArgumentNotValidException ex) {

        Map<String, String> fieldErrors = new HashMap<>();
        for (FieldError error : ex.getBindingResult().getFieldErrors()) {
            fieldErrors.put(error.getField(),
                    error.getDefaultMessage());
        }

        return ResponseEntity.badRequest().body(Map.of(
                "status", "error",
                "message", "Validation failed",
                "errors", fieldErrors,
                "timestamp", LocalDateTime.now()));
    }

    // ─── Not Found ────────────────────────────────────
    // Throw this when an entity cannot be found by ID
    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<Map<String, Object>> handleNotFound(
            NotFoundException ex) {

        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                "status", "error",
                "message", ex.getMessage(),
                "timestamp", LocalDateTime.now()));
    }

    // ─── Forbidden / Access Denied ───────────────────
    // Throw this when a user tries to access something
    // they are not authorized to touch
    @ExceptionHandler(ForbiddenException.class)
    public ResponseEntity<Map<String, Object>> handleForbidden(
            ForbiddenException ex) {

        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of(
                "status", "error",
                "message", ex.getMessage(),
                "timestamp", LocalDateTime.now()));
    }

    // ─── Business Rule Violation ─────────────────────
    // Throw this for business logic errors
    // e.g. "Order is no longer available"
    //      "Driver must be APPROVED to go online"
    //      "Account is blocked"
    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<Map<String, Object>> handleBusinessException(
            BusinessException ex) {

        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body(Map.of(
                        "status", "error",
                        "message", ex.getMessage(),
                        "timestamp", LocalDateTime.now()));
    }

    // ─── Generic RuntimeException fallback ───────────
    // For any RuntimeException not caught above.
    // Returns 400 BAD REQUEST with the exception message.
    // This covers legacy code that throws RuntimeException directly.
    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<Map<String, Object>> handleRuntimeException(
            RuntimeException ex) {

        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of(
                "status", "error",
                "message", ex.getMessage() != null
                        ? ex.getMessage()
                        : "Bad request",
                "timestamp", LocalDateTime.now()));
    }

    // ─── Unexpected server errors ─────────────────────
    // 500 — never expose internal details to client
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleGenericException(
            Exception ex) {

        // Log it internally but don't expose to client
        System.err.println("Unexpected error: " + ex.getMessage());

        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of(
                        "status", "error",
                        "message", "Something went wrong. Please try again.",
                        "timestamp", LocalDateTime.now()));
    }
}