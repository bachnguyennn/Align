package com.bachnguyennn.align.server.config;

import com.bachnguyennn.align.server.web.Problems;
import com.bachnguyennn.align.server.web.RequestSizeLimitFilter;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;

@Configuration(proxyBeanMethods = false)
public class WebConfig {

    /** Runs before Spring Security so oversized bodies are refused before any other work. */
    @Bean
    public FilterRegistrationBean<RequestSizeLimitFilter> requestSizeLimitFilter(
            AlignProperties properties, Problems problems) {
        FilterRegistrationBean<RequestSizeLimitFilter> registration =
                new FilterRegistrationBean<>(new RequestSizeLimitFilter(properties.maxRequestBytes(), problems));
        registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
        registration.addUrlPatterns("/*");
        return registration;
    }
}
