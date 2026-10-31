package com.bachnguyennn.align.server.device;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DeviceRepository extends JpaRepository<DeviceEntity, UUID> {

    Optional<DeviceEntity> findByTokenSha256(String tokenSha256);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from DeviceEntity d where d.id = :deviceId")
    int deleteDevice(@Param("deviceId") UUID deviceId);
}
