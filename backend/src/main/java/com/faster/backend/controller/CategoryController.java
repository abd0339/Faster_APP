package com.faster.backend.controller;

import com.faster.backend.dto.CategoryRequest;
import com.faster.backend.entity.Category;
import com.faster.backend.security.AuthenticatedUserResolver;
import com.faster.backend.service.CategoryService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/merchant/categories")
@RequiredArgsConstructor
public class CategoryController {

    private final CategoryService categoryService;
    private final AuthenticatedUserResolver authResolver;
    // ─── POST /api/merchant/categories ───────────────
    @PostMapping
    public ResponseEntity<?> createCategory(
            @Valid @RequestBody CategoryRequest request,
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);

        Category category = categoryService.createCategory(
                merchantId,
                request.getName(),
                request.getIcon(),
                request.getDisplayOrder());

        return ResponseEntity.ok(category);
    }

    // ─── GET /api/merchant/categories ────────────────
    @GetMapping
    public ResponseEntity<List<Category>> getCategories(
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);
        return ResponseEntity.ok(
            categoryService.getCategories(merchantId));
    }

    // ─── PUT /api/merchant/categories/{id} ───────────
    @PutMapping("/{id}")
    public ResponseEntity<?> updateCategory(
            @PathVariable Long id,
            @Valid @RequestBody CategoryRequest request,
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);

        Category updated = categoryService.updateCategory(
                merchantId,
                id,
                request.getName(),
                request.getIcon(),
                request.getDisplayOrder(),
                request.getIsActive());

        return ResponseEntity.ok(updated);
    }

    // ─── DELETE /api/merchant/categories/{id} ────────
    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteCategory(
            @PathVariable Long id,
            Authentication auth) {

        Long merchantId = authResolver.resolveId(auth);
        categoryService.deleteCategory(merchantId, id);

        return ResponseEntity.ok(
            Map.of("message",
                   "Category deleted successfully"));
    }
}