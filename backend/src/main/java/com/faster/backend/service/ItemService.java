package com.faster.backend.service;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.User;
import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.UserRepository;

import lombok.RequiredArgsConstructor;

@Service
@RequiredArgsConstructor
public class ItemService {

    private final ItemRepository itemRepository;
    private final CategoryRepository categoryRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final MenuCacheService menuCacheService;

    // ─── Create item ──────────────────────────────────
    @Transactional
    public Item createItem(Long merchantId,
                           Long categoryId,
                           String name,
                           String description,
                           BigDecimal price,
                           Integer stockQuantity,
                           Integer prepTimeMinutes,
                           BigDecimal taxRate,
                           BigDecimal serviceFee,
                           Integer displayOrder) {

        User merchant = getMerchant(merchantId);
        Category category = getCategory(
            categoryId, merchantId);

        Item item = Item.builder()
                .merchant(merchant)
                .category(category)
                .name(name)
                .description(description)
                .price(price)
                .stockQuantity(
                    stockQuantity != null
                    ? stockQuantity : -1)
                .prepTimeMinutes(
                    prepTimeMinutes != null
                    ? prepTimeMinutes : 15)
                .taxRate(taxRate != null
                    ? taxRate : BigDecimal.ZERO)
                .serviceFee(serviceFee != null
                    ? serviceFee : BigDecimal.ZERO)
                .displayOrder(
                    displayOrder != null
                    ? displayOrder : 0)
                .isAvailable(true)
                .isSnoozed(false)
                .build();

        Item saved = itemRepository.save(item);

        // Invalidate menu cache for this merchant
        menuCacheService.evictMenuCache(merchantId);

        return saved;
    }

    // ─── Upload item image ────────────────────────────
    @Transactional
    public Item uploadItemImage(Long merchantId,
                                Long itemId,
                                MultipartFile image) {
        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        // Delete old image if exists
        if (item.getImageUrl() != null) {
            fileStorageService.deleteImage(
                item.getImageUrl());
        }

        // Save new image
        String imageUrl = fileStorageService
                .saveImage(image, "items");
        item.setImageUrl(imageUrl);

        Item saved = itemRepository.save(item);
        menuCacheService.evictMenuCache(merchantId);
        return saved;
    }

    // ─── Toggle availability ──────────────────────────
    @Transactional
    public Item toggleAvailability(Long merchantId,
                                   Long itemId) {
        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        item.setIsAvailable(!item.getIsAvailable());
        Item saved = itemRepository.save(item);
        menuCacheService.evictMenuCache(merchantId);
        return saved;
    }

    // ─── Snooze item for X hours ──────────────────────
    @Transactional
    public Item snoozeItem(Long merchantId,
                           Long itemId,
                           int hours) {
        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        item.setIsSnoozed(true);
        item.setSnoozeUntil(
            LocalDateTime.now().plusHours(hours));

        Item saved = itemRepository.save(item);
        menuCacheService.evictMenuCache(merchantId);
        return saved;
    }

    // ─── Unsnooze item manually ───────────────────────
    @Transactional
    public Item unsnoozeItem(Long merchantId,
                             Long itemId) {
        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        item.setIsSnoozed(false);
        item.setSnoozeUntil(null);

        Item saved = itemRepository.save(item);
        menuCacheService.evictMenuCache(merchantId);
        return saved;
    }

    // ─── Get all items for a merchant ─────────────────
    public List<Item> getMerchantItems(Long merchantId) {
        return itemRepository
            .findByMerchantIdOrderByDisplayOrderAsc(
                merchantId);
    }

    // ─── Get single item ──────────────────────────────
    public Item getItem(Long merchantId, Long itemId) {
        return itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));
    }

    // ─── Update item ──────────────────────────────────
    @Transactional
    public Item updateItem(Long merchantId,
                           Long itemId,
                           String name,
                           String description,
                           BigDecimal price,
                           Integer stockQuantity,
                           Integer prepTimeMinutes,
                           Long categoryId) {

        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        if (name != null && !name.isBlank()) {
            item.setName(name);
        }
        if (description != null) {
            item.setDescription(description);
        }
        if (price != null) {
            item.setPrice(price);
        }
        if (stockQuantity != null) {
            item.setStockQuantity(stockQuantity);
        }
        if (prepTimeMinutes != null) {
            item.setPrepTimeMinutes(prepTimeMinutes);
        }
        if (categoryId != null) {
            Category category = getCategory(
                categoryId, merchantId);
            item.setCategory(category);
        }

        Item saved = itemRepository.save(item);
        menuCacheService.evictMenuCache(merchantId);
        return saved;
    }

    // ─── Delete item ──────────────────────────────────
    @Transactional
    public void deleteItem(Long merchantId,
                           Long itemId) {
        Item item = itemRepository
                .findByIdAndMerchantId(itemId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Item not found"));

        // Delete image from disk
        if (item.getImageUrl() != null) {
            fileStorageService.deleteImage(
                item.getImageUrl());
        }

        itemRepository.delete(item);
        menuCacheService.evictMenuCache(merchantId);
    }

    // ─── Decrement stock (called when order placed) ───
    @Transactional
    public boolean decrementStock(Long itemId, int qty) {
        int updated = itemRepository
            .decrementStock(itemId, qty);
        // Returns 0 if not enough stock
        return updated > 0;
    }

    // ─── Release stock (called when order cancelled) ──
    @Transactional
    public void releaseStock(Long itemId, int qty) {
        itemRepository.incrementStock(itemId, qty);
    }

    // ─── Auto-unsnooze every 15 minutes ──────────────
    @Scheduled(fixedRate = 900000)
    @Transactional
    public void autoUnsnooze() {
        int count = itemRepository.unsnoozeExpiredItems();
        if (count > 0) {
            System.out.println(
                "Auto-unsnoozed " + count + " items");
        }
    }

    // ─── Helpers ──────────────────────────────────────
    private User getMerchant(Long merchantId) {
        return userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Merchant not found"));
    }

    private Category getCategory(Long categoryId,
                                  Long merchantId) {
        return categoryRepository
                .findByIdAndMerchantId(
                    categoryId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Category not found or doesn't " +
                    "belong to this merchant"));
    }
}