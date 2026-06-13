package com.faster.backend.repository;

import com.faster.backend.entity.Category;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CategoryRepository extends JpaRepository<Category, Long> {

        // ─── All active categories for a merchant, ordered
        List<Category> findByMerchantIdAndIsActiveTrueOrderByDisplayOrderAsc(
                        Long merchantId);

        // ─── All categories regardless of active status (merchant view)
        List<Category> findByMerchantIdOrderByDisplayOrderAsc(Long merchantId);

        // ─── Find by id + merchant ────────────────────────
        Optional<Category> findByIdAndMerchantId(
                        Long id, Long merchantId);

        // ─── Find by name + merchant (any status) ─────────
        Optional<Category> findByNameAndMerchantId(
                        String name, Long merchantId);

        // ─── Duplicate check — ACTIVE only ────────────────
        boolean existsByNameAndMerchantIdAndIsActiveTrue(
                        String name, Long merchantId);

        // ─── Old method kept for safety ───────────────────
        boolean existsByNameAndMerchantId(
                        String name, Long merchantId);

        // ─── Count active categories ──────────────────────
        long countByMerchantIdAndIsActiveTrue(Long merchantId);

        // ─── Full menu with items ─────────────────────────
        @Query("SELECT c FROM Category c " +
                        "LEFT JOIN FETCH c.items i " +
                        "WHERE c.merchant.id = :merchantId " +
                        "AND c.isActive = true " +
                        "ORDER BY c.displayOrder ASC")
        List<Category> findFullMenuByMerchantId(
                        @Param("merchantId") Long merchantId);
}