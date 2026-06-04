package com.faster.backend.repository;

import com.faster.backend.entity.ModifierOption;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ModifierOptionRepository
        extends JpaRepository<ModifierOption, Long> {

    // ─── All options for a modifier group ────────────
    List<ModifierOption> findByModifierGroupId(Long groupId);

    // ─── Only available options ───────────────────────
    List<ModifierOption> findByModifierGroupIdAndIsAvailableTrue(
            Long groupId);

    // ─── Verify option belongs to merchant ───────────
    @Query("SELECT o FROM ModifierOption o " +
           "WHERE o.id = :optionId " +
           "AND o.modifierGroup.item.merchant.id = :merchantId")
    Optional<ModifierOption> findByIdAndMerchantId(
            @Param("optionId") Long optionId,
            @Param("merchantId") Long merchantId);
}