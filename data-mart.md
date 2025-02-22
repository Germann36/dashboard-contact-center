# Витрина данных для дашборда контакт-центра

## Общие моменты
Надо сделать витрину для дашборда контакт-центра.

## Реализация
Сначала назначим переменную по источнику клиента. Сделаем это через временную таблицу.
```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT)
;
INSERT INTO source_list (name_source) VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4')
;
```


Далее выберем из базы клиентов всех, кто обратился через указанные источники. \
Создаем обычное представление, чтобы в дальнейшем было удобно работать с получившейся таблицей.
```sql
CREATE OR REPLACE VIEW client_requests AS
SELECT *
  FROM all_client
 WHERE TRUE 
   AND promotion IN (SELECT name_source FROM source_list)
```
