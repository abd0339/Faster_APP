package com.faster.backend.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.User;
import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — CategoryService never
 * injected or called MenuCacheService, so creating/renaming/deactivating
 * or deleting a category never evicted the cached "menu::{merchantId}"
 * entry PublicMenuController serves, unlike ItemService (which evicts on
 * every item write). Without this, a merchant deactivating or deleting a
 * category kept serving the old category/items to customers for up to
 * the cache's 5-minute TTL.
 */
@ExtendWith(MockitoExtension.class)
class CategoryServiceCacheEvictionTest {

    @Mock
    private CategoryRepository categoryRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private ItemRepository itemRepository;

    @Mock
    private MenuCacheService menuCacheService;

    private CategoryService categoryService;

    private static final long MERCHANT_ID = 10L;
    private static final long CATEGORY_ID = 20L;

    @BeforeEach
    void setUp() {
        categoryService = new CategoryService(
                categoryRepository, userRepository, itemRepository, menuCacheService);
    }

    @Test
    void createCategory_evictsMenuCache() {
        when(categoryRepository.existsByNameAndMerchantIdAndIsActiveTrue("Drinks", MERCHANT_ID))
                .thenReturn(false);
        when(categoryRepository.findByNameAndMerchantId("Drinks", MERCHANT_ID))
                .thenReturn(Optional.empty());
        when(userRepository.findById(MERCHANT_ID))
                .thenReturn(Optional.of(User.builder().id(MERCHANT_ID).build()));
        when(categoryRepository.save(any(Category.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        categoryService.createCategory(MERCHANT_ID, "Drinks", null, 0);

        verify(menuCacheService, times(1)).evictMenuCache(MERCHANT_ID);
    }

    @Test
    void updateCategory_evictsMenuCache() {
        Category existing = Category.builder()
                .id(CATEGORY_ID).name("Drinks").build();
        when(categoryRepository.findByIdAndMerchantId(CATEGORY_ID, MERCHANT_ID))
                .thenReturn(Optional.of(existing));
        when(categoryRepository.save(any(Category.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        categoryService.updateCategory(MERCHANT_ID, CATEGORY_ID, null, null, null, false);

        verify(menuCacheService, times(1)).evictMenuCache(MERCHANT_ID);
    }

    @Test
    void deleteCategory_evictsMenuCache() {
        Category existing = Category.builder().id(CATEGORY_ID).build();
        when(categoryRepository.findByIdAndMerchantId(CATEGORY_ID, MERCHANT_ID))
                .thenReturn(Optional.of(existing));
        when(itemRepository.existsByCategoryId(CATEGORY_ID)).thenReturn(false);

        categoryService.deleteCategory(MERCHANT_ID, CATEGORY_ID);

        verify(menuCacheService, times(1)).evictMenuCache(MERCHANT_ID);
    }

    @Test
    void deleteCategory_withItems_rejectsAndNeverEvicts() {
        Category existing = Category.builder().id(CATEGORY_ID).build();
        when(categoryRepository.findByIdAndMerchantId(CATEGORY_ID, MERCHANT_ID))
                .thenReturn(Optional.of(existing));
        when(itemRepository.existsByCategoryId(CATEGORY_ID)).thenReturn(true);

        org.junit.jupiter.api.Assertions.assertThrows(
                com.faster.backend.exception.BusinessException.class,
                () -> categoryService.deleteCategory(MERCHANT_ID, CATEGORY_ID));

        verify(menuCacheService, never()).evictMenuCache(MERCHANT_ID);
    }
}
