package com.faster.backend.service;

import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.UserRepository;

/**
 * Full-codebase review fix round (2026-11) — the scheduled autoUnsnooze
 * job bulk-flips isSnoozed=false across all merchants but never evicted
 * the menu cache for any of them, unlike the manual snoozeItem/
 * unsnoozeItem paths. An auto-unsnoozed item stayed invisible on the
 * public menu for up to the cache's 5-minute TTL after it should have
 * reappeared, every 15-minute cycle.
 */
@ExtendWith(MockitoExtension.class)
class ItemServiceAutoUnsnoozeTest {

    @Mock
    private ItemRepository itemRepository;

    @Mock
    private CategoryRepository categoryRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private FileStorageService fileStorageService;

    @Mock
    private MenuCacheService menuCacheService;

    @Mock
    private PricingService pricingService;

    private ItemService itemService;

    @BeforeEach
    void setUp() {
        itemService = new ItemService(
                itemRepository, categoryRepository, userRepository,
                fileStorageService, menuCacheService, pricingService);
    }

    @Test
    void autoUnsnooze_clearsAllMenuCachesWhenItemsWereUnsnoozed() {
        when(itemRepository.unsnoozeExpiredItems()).thenReturn(3);

        itemService.autoUnsnooze();

        verify(menuCacheService, times(1)).clearAllMenuCaches();
    }

    @Test
    void autoUnsnooze_doesNothingWhenNoItemsWereUnsnoozed() {
        when(itemRepository.unsnoozeExpiredItems()).thenReturn(0);

        itemService.autoUnsnooze();

        verify(menuCacheService, never()).clearAllMenuCaches();
    }
}
