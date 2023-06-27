--
-- Slowly Changing Dimensions
-- przyk³ady
--

--
-- Utworzenie testowej bazy danych
--
use master;
go

create database SCDTest;
go

use SCDTest;
go

--
-- Utworzenie testowych tabel
--
create table Klienci(
	id_klienta int not null,
	nazwa nvarchar(40),
	miasto nvarchar(40));
go

create table Sprzedaz(
	id_klienta int not null,
	produkt nvarchar(40),
	data_sprzedazy date,
	kwota decimal(10,2));
go

--
-- dane przyk³adowe
--
insert Klienci values
	( 1, 'Alfa', 'Warszawa' ),
	( 2, 'Beta', 'Warszawa' ),
	( 3, 'Delta', 'Kraków' ),
	( 4, 'Gamma', 'Kraków' );
go

insert Sprzedaz values
	( 1, 'Widget', '20200329', 100 ),
	( 1, 'Gadget', '20200330', 200 ),
	( 2, 'Widget', '20200329', 100 ),
	( 2, 'Gadget', '20200402', 200 ),
	( 3, 'Widget', '20200329', 100 ),
	( 3, 'Gadget', '20200403', 200 ),
	( 4, 'Widget', '20200330', 100 ),
	( 4, 'Gadget', '20200402', 200 )
go

select * from Klienci;
select * from Sprzedaz;
go

-- 
-- widok pokazuj¹cy zagregowan¹ sprzeda¿ wg miasta i miesi¹ca
--
create view vSprzedaz as
	select
		K.miasto miasto,
		MONTH(S.data_sprzedazy) miesi¹c,
		SUM(S.kwota) sprzeda¿
	from Klienci K join Sprzedaz S on K.id_klienta = S.id_klienta
	group by K.miasto, MONTH(S.data_sprzedazy);
go

select * from vSprzedaz;

-- Wynik zapytania prezentuje aktualne dane. Zwróæ uwagê na sprzeda¿ w marcu w Krakowie - 200

-- Wprowadzamu zmianê w wymiarze - Miasto. Klient Delta przeprowadza siê z dniem 1 kwietnia 2020
-- do Warszawy.
-- W obecnej strukturze danych data przeprowadzki nie jest nigdzie rejestrowana.
update Klienci set
	miasto = 'Warszawa' 
where id_klienta = 3 

-- i ponownie wykonujemy zapytanie na widok raportowy
select * from vSprzedaz;

-- zwróæ uwagê na wartoœæ sprzeda¿y dla Krakowa i marca - teraz wynosi 100.

-- Dane za marzec s¹ danymi historycznymi. Zmiana w danych klienta zosta³a wprowadzona 1 kwietnia.
-- Jednak ta zmiana spowodowa³a "przeniesienie" historycznych danych klienta Delta z Krakowa do Warszawy.
-- Taki sposób obs³ugi zmian w wymiarze (a raczej jej brak) okreœlany jest jako
-- SCD typu 1  (Slowly Changing Dimension type 1)
select * from Klienci;


-- przywracamy oryginalne dane w tabeli Klientów
truncate table Klienci;
insert Klienci values
	( 1, 'Alfa', 'Warszawa' ),
	( 2, 'Beta', 'Warszawa' ),
	( 3, 'Delta', 'Kraków' ),
	( 4, 'Gamma', 'Kraków' );
go

--
-- SCD typu 2
--

-- SCD typu 2 oznacza, ¿e przechowujemy pe³n¹ historiê zmian.
-- Wymaga to kilku modyfikacji w strukturze tabeli Klienci oraz zmian w logice ³adowania tej tabeli ze 
-- Ÿród³a danych. Skorygowaæ nale¿y rownie¿ ³adowanie danych do tabeli faktów.

-- Za³ó¿my, ¿e tabela Klienci to tabela Ÿród³owa (np. z systemu sprzeda¿owego).
-- Tworzymy teraz tabelê, która bêdzie tabel¹ wymiaru w naszym modelu.
-- Zwróæ uwagê na dodatkowe kolumny:

create table Dim_Klienci(
	id_klienta_DW int not null identity(1,1),
	id_klienta_SRC int not null,
	nazwa nvarchar(40),
	miasto nvarchar(40),
	data_start date,
	data_koniec date,
	czy_aktualny bit);
go

-- Kolumna id_klienta_SRC to identyfikator klienta pochodz¹cy z systemu Ÿród³owego. Czêsto
-- okreœlany jako identyfikator biznesowy.
-- Kolumna id_klienta_DW to identyfikator klienta w modelu. A precyzyjniej - jest to unikalny
-- identyfikator wersji danych klienta.
-- Kolumny data_start oraz data_koniec zawieraj¹ informacjê od kiedy do kiedy dany wiersz by³
-- aktualny.
-- Kolumna czy_aktualny mo¿e stanowiæ dodatkow¹ pomoc w szybkiej selekcji wierszy zawieraj¹cych 
-- aktualne wartoœci atrybutów danego klienta.

-- Pierwsze za³adowanie tabeli (zasilanie inicjalne) tworzy pocz¹tkowe wersje wszystkich klientów.
-- Pobieramy dane z tabeli Klienci, uzupe³niaj¹c dodatkowe kolumny techniczne (audytowe).
truncate table Dim_Klienci;
go

insert Dim_Klienci 
select
	id_klienta,
	nazwa,
	miasto,
	'20200301',  -- data ³adowania jest jednoczeœnie dat¹ pocz¹tkow¹ okresu obowi¹zywania danej wersji
	null,        -- daty koñcowej obowi¹zywania wersji nie ma
	1            -- wiersz aktualny
from Klienci;
go

select * from Dim_Klienci;
go

-- tworzymy tabelê faktów
create table Fact_Sprzedaz(
	id_klienta int not null,
	produkt nvarchar(40),
	data_sprzedazy date,
	kwota decimal(10,2));
go

-- ³adujemy dane z oryginalnej tabeli sprzeda¿y, ale tylko fragment dotycz¹cy marca
insert Fact_Sprzedaz
select
  id_klienta,
  produkt,
  data_sprzedazy,
  kwota
from Sprzedaz
where MONTH(data_sprzedazy) = 3;
go

select * from Dim_Klienci;
go
select * from Fact_Sprzedaz;
go

-- Mamy stan naszych danych na 31 marca 2020 roku.

-- utwórzmy analogiczny widok na potrzeby raportowania
create view vSprzedaz_Raport as
	select
		K.miasto miasto,
		MONTH(S.data_sprzedazy) miesi¹c,
		SUM(S.kwota) sprzeda¿
	from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
	group by K.miasto, MONTH(S.data_sprzedazy);
go

-- zwróæ uwagê na kolumny definiuj¹ce relacjê pomiêdzy tabelami. Od strony
-- Dim_Klienci jest to identyfikator danych w modelu, a nie identyfikator biznesowy.

select * from vSprzedaz_Raport;
go

-- na razie nie mamy sprzeda¿y w kwietniu

-- Co powinna zrobiæ procedura ³adowania danych zgodna z SCD typu 2?
--   1. Sprawdziæ czy w wymiarach zasz³y jakieœ zmiany w wartoœciach atrybutów.
--   2. Jeœli tak - utowrzyæ w danych modelu now¹ wersjê elementu wymiaru.
--   3. Zamieniæ klucze biznesowe w wymiarach na klucze obowi¹zuj¹ce w modelu.

-- 1. Wykrycie zmian -- mo¿na do tego celu zastosowaæ ró¿ne narzêdzia, np. Change Tracking,
--    Change Data Capture, tabele temporalne, wyzwalacze w bazie Ÿród³owej, 
--    kolumny audytowe, porównania poprzez sumy kontrolne, itp.
-- My wykorzystamy proste porównanie danych.
select * from Klienci;



-- Najpierw zmiana w danych Ÿród³owych. Za³ó¿my, ¿e modyfikacjê wykonujemy 1 kwietnia.

select * from Klienci

-- Klient 3 przenosi siê z Krakowa do Warszawy
update Klienci set
	miasto = 'Warszawa' 
where id_klienta = 3 

-- wy³apujemy klientów ze zmianami (porównujemy stan z tabeli Ÿród³owej z wierszami aktualnymi tabeli wymiaru)
-- Wynik zapisujemy sobie do tabeli tymczasowej
drop table if exists #zmiany;
go

select 
	SRC.id_klienta id_klienta_SRC,
	SRC.miasto miasto_nowe,
	SRC.nazwa nazwa_nowe
into #zmiany
from Klienci SRC join Dim_Klienci WYM on SRC.id_klienta = WYM.id_klienta_SRC
where WYM.czy_aktualny = 1 
      and (SRC.miasto <> WYM.miasto or SRC.nazwa <> WYM.nazwa);

select * from #zmiany;

-- Zmiana wartoœci atrybutu wymaga DODANIA nowego wiersza do tabeli Dim_Klienci. Trzeba te¿ pamiêtaæ o "zamkniêciu"
-- aktualnego wiersza w tabeli wymiaru
 
begin transaction
	-- zamykamy aktualny wiersz z dat¹ koñca marca
	update Dim_Klienci set
		czy_aktualny = 0,
		data_koniec = '20200331'
	where id_klienta_SRC in (select id_klienta_SRC from #zmiany) and czy_aktualny = 1;

	select * from Dim_Klienci;

	-- dodajemy nowy wiersz
	insert Dim_Klienci
	select 
		id_klienta_SRC,
		nazwa_nowe,
		miasto_nowe,
		'20200401',      -- pocz¹tkowa data obowi¹zywania wersji
		null,			 -- koñcowa data
		1				 -- wiersz aktualny
	from #zmiany
	go

	select * from Dim_Klienci;
commit;

-- W tabeli Dim_Klienci istniej¹ dwa wiersze dotycz¹ce klienta Delta, mamy dwie wersje tego elementu
-- wymiaru. Posiadaj¹ one ten sam klucz biznesowy (3) - ale ró¿ni¹ siê kluczem w modelu (czasem
-- okreœlanym jako klucz "hurtowniany").
-- UWAGA! W tabeli faktów nale¿y wstawiaæ klucz z modelu!
-- Czyli nowe fakty dotycz¹ce klienta Delta musz¹ byæ oznaczane w tabeli faktów identyfikatorem 5.
-- Dane dotychczasowe pozostaj¹ bez zmian.

select * from Sprzedaz where MONTH(data_sprzedazy) = 4

select * from Dim_Klienci 
where id_klienta_SRC = 3 and czy_aktualny = 1;

-- dodajemy dane z tabeli sprzeda¿ dotycz¹ce kwietnia
insert Fact_Sprzedaz
select
  (select K.id_klienta_DW 
     from Dim_Klienci K where K.id_klienta_SRC = SRC.id_klienta 
	 and K.czy_aktualny = 1),
  SRC.produkt,
  SRC.data_sprzedazy,
  SRC.kwota
from Sprzedaz SRC
where MONTH(SRC.data_sprzedazy) = 4;
go


select * from Fact_Sprzedaz;

-- raport
select * from vSprzedaz_Raport;

-- Sprzeda¿ marcowa nie uleg³a zmianie. Lepiej bêdzie to widoczne, gdy do raportu dodamy nazwê klienta.
select
	K.miasto miasto,
	K.nazwa nazwa,
	MONTH(S.data_sprzedazy) miesi¹c,
	SUM(S.kwota) sprzeda¿
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.miasto, K.nazwa, MONTH(S.data_sprzedazy);
-- Klient Delta w wierszu dla marca jest przypisany do Krakowa. W wierszu kwietniowym - do Warszawy.

select
	K.nazwa nazwa,
	SUM(S.kwota) sprzeda¿
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa;

select
	K.nazwa nazwa, K.id_klienta_DW,
	SUM(S.kwota) sprzeda¿
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa, K.id_klienta_DW

select
	K.nazwa nazwa,
	K.miasto miasto,
	SUM(S.kwota) sprzeda¿
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa, K.miasto
order by K.nazwa;


-- SCD typu 2
-- ZALETA: pe³ne rejestrowanie historii zmian
-- WADA: skomplikowana procedura ³adowania danych ze Ÿróde³, 
--       koniecznoœæ wykrywania zmian w danych Ÿród³owych,
--       koniecznoœæ dopasowania struktur danych w tabelach modelu.

--
-- SCD typu 3
--
-- Nie rejestruje pe³nej historii zmian. Zapamiêtujemy tylko ostani¹ (jedn¹) lub wiêksz¹ (ale œciœle
-- okreœlon¹) liczbê zmian. Wykorzystujemy do tego dodatkowe kolumny w tabeli wymiaru.
-- Poni¿szy przyk³ad pos³u¿y do zapamiêtania tylko jednej, ostatniej zmiany dla jednej wybranej kolumny (miasto).

create table Dim_Klienci_SCD3(
	id_klienta int not null,	-- identyfikator biznesowy jest równie¿ identyfikatorem w modelu  
	nazwa nvarchar(40),
	miasto nvarchar(40),
	miasto_poprzednie nvarchar(40),	 -- kolumna dodatkowa
	data_zmiany date);
go

-- ³adujemy aktualn¹ tabelê klientów
insert Dim_Klienci_SCD3
select
	id_klienta,
	nazwa,
	miasto,
	null,
	null
from Klienci;

select * from Dim_Klienci_SCD3;

-- Klient Delta przenosi siê do Gdyni z dniem 1 kwietnia
update Dim_Klienci_SCD3 set
	miasto = 'Gdynia',
	miasto_poprzednie = miasto,
	data_zmiany = '20200401'
where id_klienta = 3;

select * from Dim_Klienci_SCD3;

update Dim_Klienci_SCD3 set
	miasto_poprzednie = miasto
where data_zmiany is null;

-- aktualne miasto w SCD2
select nazwa, miasto from Dim_Klienci where czy_aktualny = 1;

-- aktualne miasto w SCD3
select nazwa, miasto from Dim_Klienci_SCD3;

-- SCD Typ3
-- ZALETA: nie wymaga przemapowywania kluczy biznesowych na hurtowniane w tabeli faktów
--         jeden wiersz tabeli wymiaru odpowiada nadal jednemu elementowi danych (tu: klientowi)
-- WADA: dodatkowa jedna kolumna na ka¿d¹ zmianê ka¿dego atrybutu
--       bez zmiany treœci zapytania raportowego, dane bêd¹ siê "przenosiæ" (czasem jest to zaleta...)

-- inne, bardziej z³o¿one typy SCD opisane s¹ tutaj:
-- https://www.kimballgroup.com/2013/02/design-tip-152-slowly-changing-dimension-types-0-4-5-6-7/
-- https://www.kimballgroup.com/2005/03/slowly-changing-dimensions-are-not-always-as-easy-as-1-2-3/

use AdventureWorksDW2019;

select * from DimProduct
where EnglishProductName = 'awc logo cap';

select 
	F.ProductKey,
	SUM(F.SalesAmount)
from DimProduct P join FactInternetSales F on P.ProductKey = F.ProductKey
where P.ProductAlternateKey = 'ca-1098'
group by F.ProductKey;

