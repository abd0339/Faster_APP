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

    // ─── All categories for a merchant, ordered ──────
    List<Category> findByMerchantIdAndIsActiveTrueOrderByDisplayOrderAsc(
            Long merchantId);

    // ─── Find one category belonging to a merchant ───
    Optional<Category> findByIdAndMerchantId(
            Long id, Long merchantId);

    // ─── Check duplicate name per merchant ───────────
    boolean existsByNameAndMerchantId(
            String name, Long merchantId);

    // ─── Count active categories per merchant ────────
    long countByMerchantIdAndIsActiveTrue(Long merchantId);

    // ─── Full category with items (for menu display) ─
    @Query("SELECT c FROM Category c " +
           "LEFT JOIN FETCH c.items i " +
           "WHERE c.merchant.id = :merchantId " +
           "AND c.isActive = true " +
           "ORDER BY c.displayOrder ASC")
    List<Category> findFullMenuByMerchantId(
            @Param("merchantId") Long merchantId);
}
