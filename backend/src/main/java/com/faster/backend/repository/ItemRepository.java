package com.faster.backend.repository;

import com.faster.backend.entity.Item;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ItemRepository extends JpaRepository<Item, Long> {

        // ─── All items for a merchant ─────────────────────
        List<Item> findByMerchantIdOrderByDisplayOrderAsc(
                        Long merchantId);

        // ─── All items in a category ──────────────────────
        // ─── All items for a merchant with category eagerly loaded ──
        @Query("SELECT i FROM Item i " +
                        "LEFT JOIN FETCH i.category " +
                        "WHERE i.merchant.id = :merchantId " +
                        "ORDER BY i.displayOrder ASC")
        List<Item> findByMerchantIdWithCategory(
                        @Param("merchantId") Long merchantId);

        // ─── Find one item belonging to a merchant ────────
        Optional<Item> findByIdAndMerchantId(
                        Long id, Long merchantId);

        // ─── Bulk find, scoped to merchant — used when linking
        // items to an offer, so a merchant can't link another
        // merchant's items by guessing/incrementing IDs.
        List<Item> findByIdInAndMerchantId(
                        List<Long> ids, Long merchantId);

        // ─── Search items by name (for customer search) ───
        @Query("SELECT i FROM Item i " +
                        "WHERE i.merchant.id = :merchantId " +
                        "AND LOWER(i.name) LIKE LOWER(CONCAT('%', :name, '%')) " +
                        "AND i.isAvailable = true")
        List<Item> searchByNameAndMerchant(
                        @Param("merchantId") Long merchantId,
                        @Param("name") String name);

        // ─── DISTRIBUTED LOCK for stock updates ──────────
        // Prevents overselling when 2 orders hit at same time
        @Lock(LockModeType.PESSIMISTIC_WRITE)
        @Query("SELECT i FROM Item i WHERE i.id = :id")
        Optional<Item> findByIdWithLock(@Param("id") Long id);

        // ─── Atomic stock decrement (prevents race condition)
        @Modifying
        @Query("UPDATE Item i SET i.stockQuantity = i.stockQuantity - :qty " +
                        "WHERE i.id = :id AND i.stockQuantity >= :qty")
        int decrementStock(@Param("id") Long id,
                        @Param("qty") int qty);

        // ─── Atomic stock increment (order cancelled) ────
        @Modifying
        @Query("UPDATE Item i SET i.stockQuantity = i.stockQuantity + :qty " +
                        "WHERE i.id = :id")
        int incrementStock(@Param("id") Long id,
                        @Param("qty") int qty);

        // ─── Auto-unsnooze expired items ──────────────────
        @Modifying
        @Query("UPDATE Item i SET i.isSnoozed = false, i.snoozeUntil = null " +
                        "WHERE i.isSnoozed = true " +
                        "AND i.snoozeUntil <= CURRENT_TIMESTAMP")
        int unsnoozeExpiredItems();

        // ─── Count items per merchant ─────────────────────
        long countByMerchantId(Long merchantId);

        // ─── Is this category still in use? ──────────────
        // Used by CategoryService.deleteCategory to reject the
        // delete with a clean error instead of letting the FK
        // constraint (Item.category is non-nullable) surface as a
        // raw, unhandled 500.
        boolean existsByCategoryId(Long categoryId);
}
