package com.faster.backend.service;

import com.faster.backend.entity.Offer;
import com.faster.backend.entity.User;
import com.faster.backend.repository.OfferRepository;
import com.faster.backend.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class OfferService {

    private final OfferRepository offerRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;

    // ─── Create offer ─────────────────────────────────
    @Transactional
    public Offer createOffer(Long merchantId,
                             String title,
                             String description,
                             BigDecimal discountPercent,
                             Offer.OfferType offerType,
                             LocalDateTime startDate,
                             LocalDateTime endDate,
                             Integer usageLimit) {

        User merchant = userRepository.findById(merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Merchant not found"));

        Offer offer = Offer.builder()
                .merchant(merchant)
                .title(title)
                .description(description)
                .discountPercent(discountPercent)
                .offerType(offerType != null
                    ? offerType
                    : Offer.OfferType.PERCENTAGE)
                .startDate(startDate)
                .endDate(endDate)
                .usageLimit(usageLimit)
                .isActive(true)
                .build();

        return offerRepository.save(offer);
    }

    // ─── Upload offer banner image ────────────────────
    @Transactional
    public Offer uploadOfferImage(Long merchantId,
                                  Long offerId,
                                  MultipartFile image) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Offer not found"));

        if (offer.getImageUrl() != null) {
            fileStorageService.deleteImage(
                offer.getImageUrl());
        }

        String imageUrl = fileStorageService
                .saveImage(image, "offers");
        offer.setImageUrl(imageUrl);

        return offerRepository.save(offer);
    }

    // ─── Get all live offers right now ────────────────
    public List<Offer> getLiveOffers(Long merchantId) {
        return offerRepository.findLiveOffers(
            merchantId, LocalDateTime.now());
    }

    // ─── Get all offers (merchant dashboard) ─────────
    public List<Offer> getAllOffers(Long merchantId) {
        return offerRepository
            .findByMerchantIdOrderByCreatedAtDesc(
                merchantId);
    }

    // ─── Toggle offer active/inactive ────────────────
    @Transactional
    public Offer toggleOffer(Long merchantId,
                             Long offerId) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Offer not found"));

        offer.setIsActive(!offer.getIsActive());
        return offerRepository.save(offer);
    }

    // ─── Delete offer ─────────────────────────────────
    @Transactional
    public void deleteOffer(Long merchantId,
                            Long offerId) {
        Offer offer = offerRepository
                .findByIdAndMerchantId(offerId, merchantId)
                .orElseThrow(() -> new RuntimeException(
                    "Offer not found"));

        if (offer.getImageUrl() != null) {
            fileStorageService.deleteImage(
                offer.getImageUrl());
        }

        offerRepository.delete(offer);
    }

    // ─── Auto-expire offers every hour ───────────────
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