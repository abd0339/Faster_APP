package com.faster.backend.service;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.Offer;
import com.faster.backend.entity.User;
import com.faster.backend.exception.BusinessException;
import com.faster.backend.exception.NotFoundException;
import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.OfferRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class OfferService {

    private final OfferRepository offerRepository;
    private final UserRepository userRepository;
    private final CategoryRepository categoryRepository;
    private final ItemRepository itemRepository;
    private final FileStorageService fileStorageService;

    // ─── Create ───────────────────────────────────────
    @Transactional
    public Offer createOffer(Long merchantId,
                             String title,
                             String description,
                             BigDecimal discountPercent,
                             Offer.OfferType offerType,
                             LocalDateTime startDate,
                             LocalDateTime endDate,
                             Integer usageLimit,
                             List<Long> categoryIds,
                             List<Long> itemIds) {

        User merchant = userRepository.findById(merchantId)
                .orElseThrow(() ->
                    new NotFoundException("Merchant not found"));

        Offer offer = Offer.builder()
                .merchant(merchant)
                .title(title)
                .description(description)
                .discountPercent(discountPercent)
                .offerType(offerType != null
                    ? offerType : Offer.OfferType.PERCENTAGE)
                .startDate(startDate)
                .endDate(endDate)
                .usageLimit(usageLimit)
                .isActive(true)
                .build();

        // ─── Link categories ──────────────────────────
        if (categoryIds != null && !categoryIds.isEmpty()) {
            offer.setAppliedToCategories(resolveOwnedCategories(merchantId, categoryIds));
        }

        // ─── Link specific items ──────────────────────
        if (itemIds != null && !itemIds.isEmpty()) {
            offer.setAppliedToItems(resolveOwnedItems(merchantId, itemIds));
        }

        return offerRepository.save(offer);
    }

    // ─── Ownership-scoped bulk lookups ────────────────
    // M3-style fix: findAllById(ids) has no merchant filter at all,
    // so a merchant could link another merchant's categories/items
    // to their own offer just by guessing/incrementing IDs. These
    // resolve through the merchant-scoped repository methods instead,
    // and reject the whole request (not just silently drop the bad
    // ones) if any requested id doesn't actually belong to this
    // merchant — a merchant silently getting fewer links than they
    // asked for, with no error, is its own kind of confusing bug.
    private List<Category> resolveOwnedCategories(Long merchantId, List<Long> categoryIds) {
        List<Category> found = categoryRepository.findByIdInAndMerchantId(categoryIds, merchantId);
        if (found.size() != new HashSet<>(categoryIds).size()) {
            throw new BusinessException(
                    "One or more categories were not found in your store");
        }
        return found;
    }

    private List<Item> resolveOwnedItems(Long merchantId, List<Long> itemIds) {
        List<Item> found = itemRepository.findByIdInAndMerchantId(itemIds, merchantId);
        if (found.size() != new HashSet<>(itemIds).size()) {
            throw new BusinessException(
                    "One or more items were not found in your store");
        }
        return found;
    }

    // ─── Update ───────────────────────────────────────
    @Transactional
    public Offer updateOffer(Long merchantId,
                             Long offerId,
                             String title,
                             String description,
                             BigDecimal discountPercent,
                             Offer.OfferType offerType,
                             LocalDateTime startDate,
                             LocalDateTime endDate,
                             Integer usageLimit,
                             List<Long> categoryIds,
                             List<Long> itemIds) {

        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() ->
                    new NotFoundException("Offer not found"));

        if (title != null && !title.isBlank()) {
            offer.setTitle(title);
        }
        if (description != null) {
            offer.setDescription(description);
        }
        if (discountPercent != null) {
            offer.setDiscountPercent(discountPercent);
        }
        if (offerType != null) {
            offer.setOfferType(offerType);
        }
        // Allow setting dates to null to clear them
        offer.setStartDate(startDate);
        offer.setEndDate(endDate);

        if (usageLimit != null) {
            offer.setUsageLimit(usageLimit);
        }

        // ─── Update categories ────────────────────────
        if (categoryIds != null) {
            offer.setAppliedToCategories(
                categoryIds.isEmpty()
                    ? new ArrayList<>()
                    : resolveOwnedCategories(merchantId, categoryIds));
        }

        // ─── Update items ─────────────────────────────
        if (itemIds != null) {
            offer.setAppliedToItems(
                itemIds.isEmpty()
                    ? new ArrayList<>()
                    : resolveOwnedItems(merchantId, itemIds));
        }

        return offerRepository.save(offer);
    }

    // ─── Upload image ─────────────────────────────────
    @Transactional
    public Offer uploadOfferImage(Long merchantId,
                                  Long offerId,
                                  MultipartFile image) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() ->
                    new NotFoundException("Offer not found"));

        if (offer.getImageUrl() != null) {
            fileStorageService.deleteImage(offer.getImageUrl());
        }

        String imageUrl = fileStorageService
                .saveImage(image, "offers");
        offer.setImageUrl(imageUrl);

        return offerRepository.save(offer);
    }

    // ─── Get live offers ──────────────────────────────
    public List<Offer> getLiveOffers(Long merchantId) {
        return offerRepository.findLiveOffers(
            merchantId, LocalDateTime.now());
    }

    // ─── Get all offers ───────────────────────────────
    public List<Offer> getAllOffers(Long merchantId) {
        return offerRepository
            .findByMerchantIdOrderByCreatedAtDesc(merchantId);
    }

    // ─── Toggle ───────────────────────────────────────
    @Transactional
    public Offer toggleOffer(Long merchantId, Long offerId) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() ->
                    new NotFoundException("Offer not found"));
        offer.setIsActive(!offer.getIsActive());
        return offerRepository.save(offer);
    }

    // ─── Delete ───────────────────────────────────────
    @Transactional
    public void deleteOffer(Long merchantId, Long offerId) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() ->
                    new NotFoundException("Offer not found"));
        if (offer.getImageUrl() != null) {
            fileStorageService.deleteImage(offer.getImageUrl());
        }
        offerRepository.delete(offer);
    }

    // ─── Auto-expire every hour ───────────────────────
    @Scheduled(fixedRate = 3600000)
    @Transactional
    public void autoExpireOffers() {
        int count = offerRepository
            .expireOldOffers(LocalDateTime.now());
        if (count > 0) {
            log.info("Auto-expired {} offers", count);
        }
    }
}