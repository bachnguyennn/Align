package com.bachnguyennn.align.server.web;

/**
 * One entry of a problem's {@code errors} array. {@code field} is a JSON path such as
 * {@code events[2].startedAt}. Rejected values are never echoed.
 */
public record FieldViolation(String field, String message) {
}
