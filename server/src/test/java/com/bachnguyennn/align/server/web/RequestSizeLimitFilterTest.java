package com.bachnguyennn.align.server.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import jakarta.servlet.ServletInputStream;
import java.io.InputStream;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;

/** The streaming half of the limit: a body without Content-Length (chunked) is cut off while read. */
class RequestSizeLimitFilterTest {

    /** The wrapper counts bytes as they are read and ignores Content-Length entirely. */
    private static MockHttpServletRequest chunked(int size) {
        MockHttpServletRequest request = new MockHttpServletRequest("PUT", "/api/v1/sessions/x");
        request.setContent(new byte[size]);
        return request;
    }

    @Test
    void readingPastTheLimitThrows() throws Exception {
        RequestSizeLimitFilter.LimitedRequest request = new RequestSizeLimitFilter.LimitedRequest(chunked(101), 100);
        ServletInputStream in = request.getInputStream();
        assertThatThrownBy(in::readAllBytes).isInstanceOf(RequestSizeLimitFilter.PayloadTooLargeException.class);
    }

    @Test
    void bodyAtTheLimitIsRead() throws Exception {
        RequestSizeLimitFilter.LimitedRequest request = new RequestSizeLimitFilter.LimitedRequest(chunked(100), 100);
        try (InputStream in = request.getInputStream()) {
            assertThat(in.readAllBytes()).hasSize(100);
        }
        RequestSizeLimitFilter.LimitedRequest single = new RequestSizeLimitFilter.LimitedRequest(chunked(2), 1);
        InputStream in = single.getInputStream();
        assertThat(in.read()).isZero();
        assertThatThrownBy(in::read).isInstanceOf(RequestSizeLimitFilter.PayloadTooLargeException.class);
    }
}
