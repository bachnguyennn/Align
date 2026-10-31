/**
 * Align posture-detection reference implementation (executable spec for the Swift
 * {@code PostureDetection} module), synthetic fixture generator and evaluation.
 *
 * <p>Java port (D-015) of the Python package {@code analytics/experiments/align_reference}; file
 * and member names follow the Python modules so the two can be diffed: {@code geometry.py} →
 * {@link com.bachnguyennn.align.reference.Geometry}, {@code model.py} → the record types and
 * {@link com.bachnguyennn.align.reference.Model}, {@code motion_filter.py} →
 * {@link com.bachnguyennn.align.reference.MotionFilter}, {@code tilt.py} →
 * {@link com.bachnguyennn.align.reference.Tilt}, and so on.
 *
 * <p>The pipeline code (Geometry, MotionFilter, CalibrationService, Tilt, PostureDetector,
 * ReminderDecisionEngine, PostureMonitor) uses plain doubles and {@link java.lang.StrictMath} so
 * that it can be mirrored line-for-line in Swift and gives the same bits on every platform.
 */
package com.bachnguyennn.align.reference;
