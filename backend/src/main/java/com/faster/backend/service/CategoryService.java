package com.faster.backend.service;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.User;
import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class CategoryService {

    private final CategoryRepository categoryRepository;
    private final UserRepository userRepository;

    // ─── Create a new category ────────────────────────
    @Transactional
    public Category createCategory(Long merchantId,
                                   String name,
                                   String icon,
                                   Integer displayOrder) {
        // Check duplicate name
        if (categoryRepository
                .existsByNameAndMerchantId(name, merchantId)) {
            throw new RuntimeException(
                "Category '" + name + "' already exists");
        }

        User merchant = getMerchant(merchantId);

        Category category = Category.builder()
                .merchant(merchant)
                .name(name)
                .icon(icon)
                .displayOrder(
                    displayOrder != null ? displayOrder : 0)
                .isActive(true)
                .build();

        return categoryRepository.save(category);
    }

    // ─── Get all categories for a merchant ───────────
    public List<Category> getCategories(Long merchantId) {
        return categoryRepository
            .findByMerchantIdAndIsActiveTrueOrderByDisplayOrderAsc(
                merchantId);
    }

    // ─── Update a category ────────────────────────────
    @Transactional
    public Category updateCategory(Long merchantId,
                                   Long categoryId,
                                   String name,
                                   String icon,
                                   Integer displayOrder) {
        Category category = categoryRepository
                .findByIdAndMerchantId(categoryId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Category not found"));

        if (name != null && !name.isBlank()) {
            category.setName(name);
        }
        if (icon != null) {
            category.setIcon(icon);
        }
        if (displayOrder != null) {
            category.setDisplayOrder(displayOrder);
        }

        return categoryRepository.save(category);
    }

    // ─── Delete (soft delete) a category ─────────────
    @Transactional
    public void deleteCategory(Long merchantId,
                               Long categoryId) {
        Category category = categoryRepository
                .findByIdAndMerchantId(categoryId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Category not found"));

        category.setIsActive(false);
        categoryRepository.save(category);
    }

    // ─── Helper: get merchant user ────────────────────
    private User getMerchant(Long merchantId) {
        return userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Merchant not found"));
    }
}