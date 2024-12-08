-- 既存のchairsテーブルにtotal_distanceとtotal_distance_updated_atカラムを追加
ALTER TABLE chairs
ADD COLUMN total_distance INTEGER NOT NULL DEFAULT 0 COMMENT '総移動距離',
ADD COLUMN total_distance_updated_at DATETIME(6) COMMENT '総移動距離更新日時';

-- total_distanceとtotal_distance_updated_atカラムを更新するSQL
UPDATE chairs
        LEFT JOIN (SELECT chair_id,
                          SUM(IFNULL(distance, 0)) AS total_distance,
                          MAX(created_at)          AS total_distance_updated_at
                   FROM (SELECT chair_id,
                                created_at,
                                ABS(latitude - LAG(latitude) OVER (PARTITION BY chair_id ORDER BY created_at)) +
                                ABS(longitude - LAG(longitude) OVER (PARTITION BY chair_id ORDER BY created_at)) AS distance
                         FROM chair_locations) tmp
                   GROUP BY chair_id) distance_table ON distance_table.chair_id = chairs.id
SET chairs.total_distance = IFNULL(distance_table.total_distance, 0),
    chairs.total_distance_updated_at = distance_table.total_distance_updated_at;
