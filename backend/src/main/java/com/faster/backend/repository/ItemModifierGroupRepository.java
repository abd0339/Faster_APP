package com.faster.backend.repository;

import com.faster.backend.entity.ItemModifierGroup;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ItemModifierGroupRepository
        extends JpaRepository<ItemModifierGroup, Long> {

    // ─── All modifier groups for an item ─────────────
    List<ItemModifierGroup> findByItemId(Long itemId);

    // ─── Find group with its options loaded ──────────
    @Query("SELECT g FROM ItemModifierGroup g " +
           "LEFT JOIN FETCH g.options " +
           "WHERE g.id = :id")
    Optional<ItemModifierGroup> findByIdWithOptions(
            @Param("id") Long id);

    // ─── All groups + options for an item (for menu) ─
    @Query("SELECT g FROM ItemModifierGroup g " +
           "LEFT JOIN FETCH g.options o " +
           "WHERE g.item.id = :itemId")
    List<ItemModifierGroup> findByItemIdWithOptions(
            @Param("itemId") Long itemId);

    // ─── Verify group belongs to merchant's item ─────
    @Query("SELECT g FROM ItemModifierGroup g " +
           "WHERE g.id = :groupId " +
           "AND g.item.merchant.id = :merchantId")
    Optional<ItemModifierGroup> findByIdAndMerchantId(
            @Param("groupId") Long groupId,
            @Param("merchantId") Long merchantId);
}
