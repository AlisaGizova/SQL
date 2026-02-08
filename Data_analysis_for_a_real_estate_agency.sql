/* Анализ данных для агентства недвижимости
 * Решаем ad hoc задачи
 * 
 * Автор: Гизова Алиса
 * Дата: 10.02.2025
*/

-- Фильтрация данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Присвоение категорий объявлениям 
category AS (
	SELECT
		f.id,
		f.total_area,
		f.rooms,
		f.balcony,
		f.floor,
		-- Категория обявления по принадлежности объявления к населённым пунктам Ленинградской области или Санкт-Петербургу
		CASE
			WHEN c.city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
		END AS region_category,
		-- Категория объявления по активности объявлений
		CASE
			WHEN a.days_exposition <= 30 THEN 'до месяца'
			WHEN a.days_exposition > 30 AND a.days_exposition <= 90 THEN 'до трех месяцев'
			WHEN a.days_exposition > 90 AND a.days_exposition <= 180 THEN 'до полугода'
			WHEN a.days_exposition >= 180 THEN 'более полугода'
		END AS days_exposition_category,
		a.last_price/f.total_area::float AS sqr_meter_price
	FROM 
		real_estate.flats AS f
		JOIN real_estate.advertisement AS a USING(id)
		LEFT JOIN real_estate.city AS c USING(city_id)
		LEFT JOIN real_estate.type AS t USING(type_id)
	WHERE 
		f.id IN (SELECT * FROM filtered_id)
		AND a.days_exposition IS NOT NULL
		AND t.type = 'город'
),
-- Количество объявлений в разрезе региона
count_ads_per_region AS (
	SELECT
		id,
		COUNT(id) OVER(PARTITION BY region_category) AS count_ads_per_region
	FROM category
)
-- Характеристики объявлений
SELECT
	-- Принадлежность объявления к Ленинградской области или Санкт-Петербургу
	c.region_category,
	-- Категория объявления по активности объявлений
	c.days_exposition_category,
	-- Количество объявлений
	COUNT(c.id) AS count_ads,
	-- Доля объявлений в разрезе каждого региона
	ROUND(COUNT(c.id)::numeric / AVG((r.count_ads_per_region)), 3) AS ads_share,
	-- Средняя стоимость квадратного метра
	ROUND(AVG(c.sqr_meter_price)::numeric) AS avg_sqr_meter_price,
	-- Средняя площадь недвижимости
	ROUND(AVG(c.total_area)::numeric) AS avg_total_area,
	-- Медиана количества комнат
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY c.rooms) AS median_rooms,
	-- Медиана количества балконов
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY c.balcony) AS median_balcony,
	-- Медиана этажности
	PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY c.floor) AS median_floor
FROM category AS c
JOIN count_ads_per_region AS r USING (id)
GROUP BY c.region_category, c.days_exposition_category;


-- Задача 2: Сезонность объявлений
-- Вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Вычисление даты снятия объявления с публикации
last_day_exposition AS (
	SELECT
		id,
		first_day_exposition,
		last_price,
		first_day_exposition + days_exposition::int AS last_day_exposition
	FROM real_estate.advertisement
	WHERE 
		days_exposition IS NOT NULL
		AND first_day_exposition >= '01-01-2015'
		AND first_day_exposition < '01-01-2019'
),
-- Выделение месяцев публикации и снятия объявления
months AS (
	SELECT
		f.id,
		f.total_area,
		EXTRACT(MONTH FROM l.first_day_exposition) AS start_exposition_month,
		EXTRACT(MONTH FROM l.last_day_exposition) AS end_exposition_month,
		l.last_price/f.total_area::float AS sqr_meter_price
	FROM real_estate.flats AS f
	JOIN last_day_exposition AS l USING(id)
	JOIN real_estate.type AS t USING(type_id)
	WHERE 
		f.id IN (SELECT * FROM filtered_id)
		AND t.type = 'город'
),
-- Публикация объявлений
start_exposition AS(
	SELECT
		DISTINCT start_exposition_month AS month,
		DENSE_RANK() OVER(ORDER BY COUNT(id) DESC) AS start_exposition_rank,
		ROUND(AVG(sqr_meter_price)::numeric) AS avg_sqr_meter_price,
		ROUND(AVG(total_area)::numeric) AS avg_total_area,
		ROUND(COUNT(id)::numeric/(SELECT COUNT(id) FROM months), 3) AS start_exposition_share
	FROM months
	GROUP BY month
	ORDER BY month
),
-- Снятие недвижимости с продажи
end_exposition AS(
	SELECT
		DISTINCT end_exposition_month AS month,
		DENSE_RANK() OVER(ORDER BY COUNT(id) DESC) AS end_exposition_rank,
		ROUND(COUNT(id)::numeric/(SELECT COUNT(id) FROM months), 3) AS end_exposition_share
	FROM months
	GROUP BY month
	ORDER BY month
)
-- Характеристики объявлений по месяцам
SELECT
	-- Месяц
	s.month,
	-- Ранг активности объявлений по публикации
	s.start_exposition_rank,
	-- Ранг активности объявлений по снятию недвижимости с продажи
	e.end_exposition_rank,
	-- Средняя стоимость квадратного метра
	s.avg_sqr_meter_price,
	-- Средняя площадь недвижимости
	s.avg_total_area,
	-- Доля количества публикаций
	s.start_exposition_share,
	-- Доля снятия объявлений
	e.end_exposition_share
FROM start_exposition AS s
JOIN end_exposition AS e USING(month)
ORDER BY month;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Топ-15 населенных пунктов Ленинградской области по количеству объявлений
top_of_city AS (
	SELECT
		DISTINCT c.city,
		COUNT(f.id) AS count_ads,
		AVG(a.last_price/f.total_area::float) AS avg_sqr_meter_price,
		AVG(f.total_area) AS avg_total_area
	FROM real_estate.flats AS f
	JOIN real_estate.advertisement AS a USING(id)
	JOIN real_estate.city AS c USING(city_id)
	WHERE c.city <> 'Санкт-Петербург'
	GROUP BY c.city
	ORDER BY count_ads DESC
	LIMIT 15
),
-- Снятые с публикации объявления
end_ads AS (
	SELECT
		c.city,
		COUNT(a.id) AS count_end_ads,
		AVG(a.days_exposition) AS avg_ad_exposition_duration
	FROM real_estate.flats AS f
	JOIN real_estate.advertisement AS a USING(id)
	JOIN real_estate.city AS c USING(city_id)
	WHERE a.days_exposition IS NOT NULL
	GROUP BY c.city
)
-- Характеристики объявлений
SELECT
	-- Название населенного пункта
	t.city,
	-- Количество опубликованных объявлений
	t.count_ads,
	-- Группы по количеству опубликованных объявлений
    NTILE(5) OVER (ORDER BY t.count_ads DESC) AS count_ads_group,
	-- Доля снятых с публикации объявлений
	ROUND(e.count_end_ads/t.count_ads::numeric, 3) AS end_ads_share,
	-- Средняя стоимость квадратного метра
	ROUND(t.avg_sqr_meter_price::numeric) AS avg_sqr_meter_price,
	-- Средняя площадь недвижимости
	ROUND(t.avg_total_area::numeric) AS avg_total_area,
	-- Средняя продолжительность публикации объявления
	ROUND(e.avg_ad_exposition_duration::numeric) AS avg_ad_exposition_duration
FROM top_of_city AS t
JOIN end_ads AS e USING(city)
ORDER BY count_ads_group;