package com.bachnguyennn.align.server.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Deploy-time settings under {@code align.*}.
 *
 * @param maxRequestBytes largest accepted request body; larger bodies are rejected with 413
 */
@ConfigurationProperties("align")
public record AlignProperties(@DefaultValue("524288") long maxRequestBytes) {
}
