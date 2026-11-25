package com.faster.backend.exception;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.core.MethodParameter;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;

/**
 * Full-codebase review fix round (2026-11) — handleValidationErrors used
 * to hardcode "message" to the literal string "Validation failed"; the
 * real per-field reason only ever reached "errors", which the Flutter
 * frontend's ApiService.getErrorMessage() never reads. A merchant typing
 * an invalid price or an over-length name saw only "Validation failed"
 * with no indication of which field or why.
 */
class GlobalExceptionHandlerValidationMessageTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    void handleValidationErrors_surfacesTheRealFieldReasonAsMessage() throws NoSuchMethodException {
        BeanPropertyBindingResult bindingResult =
                new BeanPropertyBindingResult(new Object(), "itemRequest");
        bindingResult.addError(new FieldError(
                "itemRequest", "price", "Price must be greater than 0"));

        MethodParameter methodParameter = new MethodParameter(
                this.getClass().getDeclaredMethod(
                        "handleValidationErrors_surfacesTheRealFieldReasonAsMessage"),
                -1);
        MethodArgumentNotValidException ex =
                new MethodArgumentNotValidException(methodParameter, bindingResult);

        ResponseEntity<Map<String, Object>> response = handler.handleValidationErrors(ex);

        String message = (String) response.getBody().get("message");
        assertTrue(message.contains("price"),
                "message should name the field, not just say 'Validation failed': " + message);
        assertTrue(message.contains("Price must be greater than 0"));

        @SuppressWarnings("unchecked")
        Map<String, String> errors = (Map<String, String>) response.getBody().get("errors");
        assertEquals("Price must be greater than 0", errors.get("price"));
    }
}
