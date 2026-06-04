package com.faster.backend.repository;

import com.faster.backend.entity.ItemAddon;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ItemAddonRepository
        extends JpaRepository<ItemAddon, Long> {

    // ─── All addons for an item ───────────────────────
    List<ItemAddon> findByItemId(Long itemId);

    // ─── Only available addons ────────────────────────
    List<ItemAddon> findByItemIdAndIsAvailableTrue(
            Long itemId);

    // ─── Verify addon belongs to merchant ────────────
    @Query("SELECT a FROM ItemAddon a " +
           "WHERE a.id = :addonId " +
           "AND a.item.merchant.id = :merchantId")
    Optional<ItemAddon> findByIdAndMerchantId(
            @Param("addonId") Long addonId,
            @Param("merchantId") Long merchantId);
}
