package com.faster.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.faster.backend.dto.OrderItemLineRequest;
import com.faster.backend.entity.Item;
import com.faster.backend.entity.OrderItemLine;
import com.faster.backend.entity.User;
import com.faster.backend.repository.ItemAddonRepository;
import com.faster.backend.repository.ItemRepository;
import com.faster.backend.repository.ModifierOptionRepository;
import com.faster.backend.repository.OrderItemLineRepository;

/**
 * Full-codebase review fix round (2026-11) — ItemService.releaseStock
 * existed specifically to reverse the stock decrement made at order
 * creation but had zero callers anywhere in the codebase, so a cancelled
 * order's stock was never given back. decrementStockForOrder now records
 * an OrderItemLine per line so restoreStockForOrder (called from
 * OrderService's cancel/dispute-resolution paths) has something to
 * replay.
 */
@ExtendWith(MockitoExtension.class)
class PricingServiceStockRestoreTest {

    @Mock
    private ItemRepository itemRepository;

    @Mock
    private ModifierOptionRepository modifierOptionRepository;

    @Mock
    private ItemAddonRepository addonRepository;

    @Mock
    private OrderItemLineRepository orderItemLineRepository;

    @Mock
    private MenuCacheService menuCacheService;

    private PricingService pricingService;

    private static final long ORDER_ID = 42L;
    private static final long ITEM_ID = 7L;
    private static final long UNLIMITED_ITEM_ID = 8L;
    private static final long MERCHANT_ID = 100L;

    @BeforeEach
    void setUp() {
        pricingService = new PricingService(
                itemRepository, modifierOptionRepository, addonRepository,
                orderItemLineRepository, menuCacheService);
    }

    @Test
    void decrementStockForOrder_recordsOrderItemLineAndDecrementsFiniteStock() {
        Item finiteStockItem = Item.builder().id(ITEM_ID).stockQuantity(10).build();
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(finiteStockItem));

        OrderItemLineRequest line = new OrderItemLineRequest();
        line.setItemId(ITEM_ID);
        line.setQuantity(3);

        pricingService.decrementStockForOrder(ORDER_ID, List.of(line));

        verify(itemRepository, times(1)).decrementStock(ITEM_ID, 3);

        ArgumentCaptor<OrderItemLine> captor = ArgumentCaptor.forClass(OrderItemLine.class);
        verify(orderItemLineRepository, times(1)).save(captor.capture());
        assertEquals(ORDER_ID, captor.getValue().getOrderId());
        assertEquals(ITEM_ID, captor.getValue().getItemId());
        assertEquals(3, captor.getValue().getQuantity());
    }

    @Test
    void decrementStockForOrder_skipsDecrementButStillRecordsLineForUnlimitedStock() {
        Item unlimitedItem = Item.builder().id(UNLIMITED_ITEM_ID).stockQuantity(-1).build();
        when(itemRepository.findById(UNLIMITED_ITEM_ID)).thenReturn(Optional.of(unlimitedItem));

        OrderItemLineRequest line = new OrderItemLineRequest();
        line.setItemId(UNLIMITED_ITEM_ID);
        line.setQuantity(5);

        pricingService.decrementStockForOrder(ORDER_ID, List.of(line));

        verify(itemRepository, never()).decrementStock(anyLong(), anyInt());
        verify(orderItemLineRepository, times(1)).save(any(OrderItemLine.class));
    }

    @Test
    void decrementStockForOrder_evictsMenuCacheForTheItemsMerchant() {
        Item item = Item.builder().id(ITEM_ID).stockQuantity(10)
                .merchant(User.builder().id(MERCHANT_ID).build())
                .build();
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));

        OrderItemLineRequest line = new OrderItemLineRequest();
        line.setItemId(ITEM_ID);
        line.setQuantity(2);

        pricingService.decrementStockForOrder(ORDER_ID, List.of(line));

        verify(menuCacheService, times(1)).evictMenuCache(MERCHANT_ID);
    }

    @Test
    void restoreStockForOrder_evictsMenuCacheForTheItemsMerchant() {
        OrderItemLine finiteLine = OrderItemLine.builder()
                .orderId(ORDER_ID).itemId(ITEM_ID).quantity(2).build();
        when(orderItemLineRepository.findByOrderId(ORDER_ID))
                .thenReturn(List.of(finiteLine));
        when(itemRepository.findById(ITEM_ID))
                .thenReturn(Optional.of(Item.builder().id(ITEM_ID).stockQuantity(5)
                        .merchant(User.builder().id(MERCHANT_ID).build())
                        .build()));

        pricingService.restoreStockForOrder(ORDER_ID);

        verify(menuCacheService, times(1)).evictMenuCache(MERCHANT_ID);
    }

    @Test
    void restoreStockForOrder_incrementsFiniteStockItemsOnly() {
        OrderItemLine finiteLine = OrderItemLine.builder()
                .orderId(ORDER_ID).itemId(ITEM_ID).quantity(3).build();
        OrderItemLine unlimitedLine = OrderItemLine.builder()
                .orderId(ORDER_ID).itemId(UNLIMITED_ITEM_ID).quantity(5).build();

        when(orderItemLineRepository.findByOrderId(ORDER_ID))
                .thenReturn(List.of(finiteLine, unlimitedLine));
        when(itemRepository.findById(ITEM_ID))
                .thenReturn(Optional.of(Item.builder().id(ITEM_ID).stockQuantity(7).build()));
        when(itemRepository.findById(UNLIMITED_ITEM_ID))
                .thenReturn(Optional.of(Item.builder().id(UNLIMITED_ITEM_ID).stockQuantity(-1).build()));

        pricingService.restoreStockForOrder(ORDER_ID);

        verify(itemRepository, times(1)).incrementStock(ITEM_ID, 3);
        verify(itemRepository, never()).incrementStock(eq(UNLIMITED_ITEM_ID), anyInt());
    }
}
