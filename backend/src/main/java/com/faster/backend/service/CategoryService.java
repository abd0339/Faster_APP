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

    // ─── Create ───────────────────────────────────────
    @Transactional
    public Category createCategory(Long merchantId,
                                   String name,
                                   String icon,
                                   Integer displayOrder) {

        // Check duplicate — ACTIVE rows only
        if (categoryRepository
                .existsByNameAndMerchantIdAndIsActiveTrue(name, merchantId)) {
            throw new RuntimeException(
                "Category '" + name + "' already exists");
        }

        // If a soft-deleted row with same name exists → reactivate it
        Category existing = categoryRepository
                .findByNameAndMerchantId(name, merchantId)
                .orElse(null);

        if (existing != null) {
            existing.setIsActive(true);
            existing.setIcon(icon != null ? icon : existing.getIcon());
            existing.setDisplayOrder(
                displayOrder != null ? displayOrder : existing.getDisplayOrder());
            return categoryRepository.save(existing);
        }

        // Brand new row
        User merchant = getMerchant(merchantId);
        Category category = Category.builder()
                .merchant(merchant)
                .name(name)
                .icon(icon)
                .displayOrder(displayOrder != null ? displayOrder : 0)
                .isActive(true)
                .build();

        return categoryRepository.save(category);
    }

    // ─── Get all active categories ────────────────────
    public List<Category> getCategories(Long merchantId) {
    return categoryRepository
        .findByMerchantIdOrderByDisplayOrderAsc(merchantId);
}

    // ─── Update (name + icon + isActive) ──────────────
    @Transactional
    public Category updateCategory(Long merchantId,
                                   Long categoryId,
                                   String name,
                                   String icon,
                                   Integer displayOrder,
                                   Boolean isActive) {

        Category category = categoryRepository
                .findByIdAndMerchantId(categoryId, merchantId)
                .orElseThrow(() -> new RuntimeException("Category not found"));

        if (name != null && !name.isBlank()) {
            // Check name clash only against OTHER active categories
            boolean nameClash = categoryRepository
                    .existsByNameAndMerchantIdAndIsActiveTrue(name, merchantId)
                    && !category.getName().equals(name);
            if (nameClash) {
                throw new RuntimeException(
                    "Category '" + name + "' already exists");
            }
            category.setName(name);
        }
        if (icon != null) {
            category.setIcon(icon);
        }
        if (isActive != null) {
            category.setIsActive(isActive);
        }
        if (displayOrder != null) {
            category.setDisplayOrder(displayOrder);
        }

        return categoryRepository.save(category);
    }

    // ─── Hard delete ──────────────────────────────────
    @Transactional
    public void deleteCategory(Long merchantId, Long categoryId) {
        Category category = categoryRepository
                .findByIdAndMerchantId(categoryId, merchantId)
                .orElseThrow(() -> new RuntimeException("Category not found"));

        categoryRepository.delete(category);
    }

    // ─── Helper ───────────────────────────────────────
    private User getMerchant(Long merchantId) {
        return userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException("Merchant not found"));
    }
}