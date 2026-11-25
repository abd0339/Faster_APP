package com.faster.backend.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.faster.backend.entity.OrderItemLine;

public interface OrderItemLineRepository extends JpaRepository<OrderItemLine, Long> {

    List<OrderItemLine> findByOrderId(Long orderId);
}
