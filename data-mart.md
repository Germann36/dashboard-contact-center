# Витрина данных для дашборда контакт-центра

## Общие моменты
Надо сделать витрину для дашборда контакт-центра.

Сначала назначим переменную по источнику клиента
```sql
CREATE TEMPORARY TABLE source_list (name_source TEXT)
;
INSERT INTO source_list (name_source) VALUES ('source 1'), ('source 2'), ('source 3'), ('source 4')
;
```
