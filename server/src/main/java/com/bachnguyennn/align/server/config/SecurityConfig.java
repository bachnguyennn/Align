package com.bachnguyennn.align.server.config;

import com.bachnguyennn.align.server.auth.BearerTokenAuthenticationFilter;
import com.bachnguyennn.align.server.auth.ProblemAuthenticationEntryPoint;
import com.bachnguyennn.align.server.auth.TokenService;
import com.bachnguyennn.align.server.device.DeviceRepository;
import com.bachnguyennn.align.server.web.ProblemType;
import com.bachnguyennn.align.server.web.Problems;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;

@Configuration(proxyBeanMethods = false)
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, TokenService tokens,
            DeviceRepository devices, Problems problems) throws Exception {
        // Stateless bearer-token API: no cookies, sessions, CSRF tokens, forms or basic auth.
        http.csrf(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .logout(AbstractHttpConfigurer::disable)
                .requestCache(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .addFilterBefore(new BearerTokenAuthenticationFilter(tokens, devices),
                        AnonymousAuthenticationFilter.class)
                .exceptionHandling(handling -> handling
                        .authenticationEntryPoint(new ProblemAuthenticationEntryPoint(problems))
                        .accessDeniedHandler((request, response, denied) ->
                                problems.write(request, response, ProblemType.FORBIDDEN, "Access denied.")))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.POST, "/api/v1/devices").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/health", "/api/v1/health/**").permitAll()
                        .requestMatchers("/error").permitAll()
                        .anyRequest().authenticated());
        return http.build();
    }
}
