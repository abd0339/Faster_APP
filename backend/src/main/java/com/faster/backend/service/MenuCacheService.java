package com.faster.backend.service;

import com.faster.backend.entity.Category;
import com.faster.backend.repository.CategoryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class MenuCacheService {

    private final CategoryRepository categoryRepository;

    // ─── Get full menu (cached 5 min in Redis) ────────
    // Cache key: "menu::123" (merchantId)
    @Cacheable(value = "menu",
               key = "#merchantId")
    public List<Category> getFullMenu(Long merchantId) {
        return categoryRepository
            .findFullMenuByMerchantId(merchantId);
    }

    // ─── Evict cache when menu changes ───────────────
    @CacheEvict(value = "menu",
                key = "#merchantId")
    public void evictMenuCache(Long merchantId) {
        // Spring auto-clears the cache entry
        // This runs whenever item/category changes
    }

    // ─── Clear ALL menu caches (admin use) ───────────
    @CacheEvict(value = "menu",
                allEntries = true)
    public void clearAllMenuCaches() {
        // Clears all cached menus
    }
}
