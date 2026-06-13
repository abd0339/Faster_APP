package com.faster.backend.service;

import com.faster.backend.entity.Category;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.Offer;
import com.faster.backend.entity.User;
import com.faster.backend.repository.CategoryRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.OfferRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
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
                    new RuntimeException("Merchant not found"));

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
            List<Category> cats = categoryRepository
                .findAllById(categoryIds);
            offer.setAppliedToCategories(cats);
        }

        // ─── Link specific items ──────────────────────
        if (itemIds != null && !itemIds.isEmpty()) {
            List<Item> items = itemRepository
                .findAllById(itemIds);
            offer.setAppliedToItems(items);
        }

        return offerRepository.save(offer);
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
                    new RuntimeException("Offer not found"));

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
                    : categoryRepository.findAllById(categoryIds));
        }

        // ─── Update items ─────────────────────────────
        if (itemIds != null) {
            offer.setAppliedToItems(
                itemIds.isEmpty()
                    ? new ArrayList<>()
                    : itemRepository.findAllById(itemIds));
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
                    new RuntimeException("Offer not found"));

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
                    new RuntimeException("Offer not found"));
        offer.setIsActive(!offer.getIsActive());
        return offerRepository.save(offer);
    }

    // ─── Delete ───────────────────────────────────────
    @Transactional
    public void deleteOffer(Long merchantId, Long offerId) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() ->
                    new RuntimeException("Offer not found"));
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
            System.out.println(
                "Auto-expired " + count + " offers");
        }
    }
}