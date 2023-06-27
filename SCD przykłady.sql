--
-- Slowly Changing Dimensions
-- przyk�ady
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
-- dane przyk�adowe
--
insert Klienci values
	( 1, 'Alfa', 'Warszawa' ),
	( 2, 'Beta', 'Warszawa' ),
	( 3, 'Delta', 'Krak�w' ),
	( 4, 'Gamma', 'Krak�w' );
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
-- widok pokazuj�cy zagregowan� sprzeda� wg miasta i miesi�ca
--
create view vSprzedaz as
	select
		K.miasto miasto,
		MONTH(S.data_sprzedazy) miesi�c,
		SUM(S.kwota) sprzeda�
	from Klienci K join Sprzedaz S on K.id_klienta = S.id_klienta
	group by K.miasto, MONTH(S.data_sprzedazy);
go

select * from vSprzedaz;

-- Wynik zapytania prezentuje aktualne dane. Zwr�� uwag� na sprzeda� w marcu w Krakowie - 200

-- Wprowadzamu zmian� w wymiarze - Miasto. Klient Delta przeprowadza si� z dniem 1 kwietnia 2020
-- do Warszawy.
-- W obecnej strukturze danych data przeprowadzki nie jest nigdzie rejestrowana.
update Klienci set
	miasto = 'Warszawa' 
where id_klienta = 3 

-- i ponownie wykonujemy zapytanie na widok raportowy
select * from vSprzedaz;

-- zwr�� uwag� na warto�� sprzeda�y dla Krakowa i marca - teraz wynosi 100.

-- Dane za marzec s� danymi historycznymi. Zmiana w danych klienta zosta�a wprowadzona 1 kwietnia.
-- Jednak ta zmiana spowodowa�a "przeniesienie" historycznych danych klienta Delta z Krakowa do Warszawy.
-- Taki spos�b obs�ugi zmian w wymiarze (a raczej jej brak) okre�lany jest jako
-- SCD typu 1  (Slowly Changing Dimension type 1)
select * from Klienci;


-- przywracamy oryginalne dane w tabeli Klient�w
truncate table Klienci;
insert Klienci values
	( 1, 'Alfa', 'Warszawa' ),
	( 2, 'Beta', 'Warszawa' ),
	( 3, 'Delta', 'Krak�w' ),
	( 4, 'Gamma', 'Krak�w' );
go

--
-- SCD typu 2
--

-- SCD typu 2 oznacza, �e przechowujemy pe�n� histori� zmian.
-- Wymaga to kilku modyfikacji w strukturze tabeli Klienci oraz zmian w logice �adowania tej tabeli ze 
-- �r�d�a danych. Skorygowa� nale�y rownie� �adowanie danych do tabeli fakt�w.

-- Za��my, �e tabela Klienci to tabela �r�d�owa (np. z systemu sprzeda�owego).
-- Tworzymy teraz tabel�, kt�ra b�dzie tabel� wymiaru w naszym modelu.
-- Zwr�� uwag� na dodatkowe kolumny:

create table Dim_Klienci(
	id_klienta_DW int not null identity(1,1),
	id_klienta_SRC int not null,
	nazwa nvarchar(40),
	miasto nvarchar(40),
	data_start date,
	data_koniec date,
	czy_aktualny bit);
go

-- Kolumna id_klienta_SRC to identyfikator klienta pochodz�cy z systemu �r�d�owego. Cz�sto
-- okre�lany jako identyfikator biznesowy.
-- Kolumna id_klienta_DW to identyfikator klienta w modelu. A precyzyjniej - jest to unikalny
-- identyfikator wersji danych klienta.
-- Kolumny data_start oraz data_koniec zawieraj� informacj� od kiedy do kiedy dany wiersz by�
-- aktualny.
-- Kolumna czy_aktualny mo�e stanowi� dodatkow� pomoc w szybkiej selekcji wierszy zawieraj�cych 
-- aktualne warto�ci atrybut�w danego klienta.

-- Pierwsze za�adowanie tabeli (zasilanie inicjalne) tworzy pocz�tkowe wersje wszystkich klient�w.
-- Pobieramy dane z tabeli Klienci, uzupe�niaj�c dodatkowe kolumny techniczne (audytowe).
truncate table Dim_Klienci;
go

insert Dim_Klienci 
select
	id_klienta,
	nazwa,
	miasto,
	'20200301',  -- data �adowania jest jednocze�nie dat� pocz�tkow� okresu obowi�zywania danej wersji
	null,        -- daty ko�cowej obowi�zywania wersji nie ma
	1            -- wiersz aktualny
from Klienci;
go

select * from Dim_Klienci;
go

-- tworzymy tabel� fakt�w
create table Fact_Sprzedaz(
	id_klienta int not null,
	produkt nvarchar(40),
	data_sprzedazy date,
	kwota decimal(10,2));
go

-- �adujemy dane z oryginalnej tabeli sprzeda�y, ale tylko fragment dotycz�cy marca
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

-- utw�rzmy analogiczny widok na potrzeby raportowania
create view vSprzedaz_Raport as
	select
		K.miasto miasto,
		MONTH(S.data_sprzedazy) miesi�c,
		SUM(S.kwota) sprzeda�
	from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
	group by K.miasto, MONTH(S.data_sprzedazy);
go

-- zwr�� uwag� na kolumny definiuj�ce relacj� pomi�dzy tabelami. Od strony
-- Dim_Klienci jest to identyfikator danych w modelu, a nie identyfikator biznesowy.

select * from vSprzedaz_Raport;
go

-- na razie nie mamy sprzeda�y w kwietniu

-- Co powinna zrobi� procedura �adowania danych zgodna z SCD typu 2?
--   1. Sprawdzi� czy w wymiarach zasz�y jakie� zmiany w warto�ciach atrybut�w.
--   2. Je�li tak - utowrzy� w danych modelu now� wersj� elementu wymiaru.
--   3. Zamieni� klucze biznesowe w wymiarach na klucze obowi�zuj�ce w modelu.

-- 1. Wykrycie zmian -- mo�na do tego celu zastosowa� r�ne narz�dzia, np. Change Tracking,
--    Change Data Capture, tabele temporalne, wyzwalacze w bazie �r�d�owej, 
--    kolumny audytowe, por�wnania poprzez sumy kontrolne, itp.
-- My wykorzystamy proste por�wnanie danych.
select * from Klienci;



-- Najpierw zmiana w danych �r�d�owych. Za��my, �e modyfikacj� wykonujemy 1 kwietnia.

select * from Klienci

-- Klient 3 przenosi si� z Krakowa do Warszawy
update Klienci set
	miasto = 'Warszawa' 
where id_klienta = 3 

-- wy�apujemy klient�w ze zmianami (por�wnujemy stan z tabeli �r�d�owej z wierszami aktualnymi tabeli wymiaru)
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

-- Zmiana warto�ci atrybutu wymaga DODANIA nowego wiersza do tabeli Dim_Klienci. Trzeba te� pami�ta� o "zamkni�ciu"
-- aktualnego wiersza w tabeli wymiaru
 
begin transaction
	-- zamykamy aktualny wiersz z dat� ko�ca marca
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
		'20200401',      -- pocz�tkowa data obowi�zywania wersji
		null,			 -- ko�cowa data
		1				 -- wiersz aktualny
	from #zmiany
	go

	select * from Dim_Klienci;
commit;

-- W tabeli Dim_Klienci istniej� dwa wiersze dotycz�ce klienta Delta, mamy dwie wersje tego elementu
-- wymiaru. Posiadaj� one ten sam klucz biznesowy (3) - ale r�ni� si� kluczem w modelu (czasem
-- okre�lanym jako klucz "hurtowniany").
-- UWAGA! W tabeli fakt�w nale�y wstawia� klucz z modelu!
-- Czyli nowe fakty dotycz�ce klienta Delta musz� by� oznaczane w tabeli fakt�w identyfikatorem 5.
-- Dane dotychczasowe pozostaj� bez zmian.

select * from Sprzedaz where MONTH(data_sprzedazy) = 4

select * from Dim_Klienci 
where id_klienta_SRC = 3 and czy_aktualny = 1;

-- dodajemy dane z tabeli sprzeda� dotycz�ce kwietnia
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

-- Sprzeda� marcowa nie uleg�a zmianie. Lepiej b�dzie to widoczne, gdy do raportu dodamy nazw� klienta.
select
	K.miasto miasto,
	K.nazwa nazwa,
	MONTH(S.data_sprzedazy) miesi�c,
	SUM(S.kwota) sprzeda�
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.miasto, K.nazwa, MONTH(S.data_sprzedazy);
-- Klient Delta w wierszu dla marca jest przypisany do Krakowa. W wierszu kwietniowym - do Warszawy.

select
	K.nazwa nazwa,
	SUM(S.kwota) sprzeda�
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa;

select
	K.nazwa nazwa, K.id_klienta_DW,
	SUM(S.kwota) sprzeda�
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa, K.id_klienta_DW

select
	K.nazwa nazwa,
	K.miasto miasto,
	SUM(S.kwota) sprzeda�
from Dim_Klienci K join Fact_Sprzedaz S on K.id_klienta_DW = S.id_klienta
group by K.nazwa, K.miasto
order by K.nazwa;


-- SCD typu 2
-- ZALETA: pe�ne rejestrowanie historii zmian
-- WADA: skomplikowana procedura �adowania danych ze �r�de�, 
--       konieczno�� wykrywania zmian w danych �r�d�owych,
--       konieczno�� dopasowania struktur danych w tabelach modelu.

--
-- SCD typu 3
--
-- Nie rejestruje pe�nej historii zmian. Zapami�tujemy tylko ostani� (jedn�) lub wi�ksz� (ale �ci�le
-- okre�lon�) liczb� zmian. Wykorzystujemy do tego dodatkowe kolumny w tabeli wymiaru.
-- Poni�szy przyk�ad pos�u�y do zapami�tania tylko jednej, ostatniej zmiany dla jednej wybranej kolumny (miasto).

create table Dim_Klienci_SCD3(
	id_klienta int not null,	-- identyfikator biznesowy jest r�wnie� identyfikatorem w modelu  
	nazwa nvarchar(40),
	miasto nvarchar(40),
	miasto_poprzednie nvarchar(40),	 -- kolumna dodatkowa
	data_zmiany date);
go

-- �adujemy aktualn� tabel� klient�w
insert Dim_Klienci_SCD3
select
	id_klienta,
	nazwa,
	miasto,
	null,
	null
from Klienci;

select * from Dim_Klienci_SCD3;

-- Klient Delta przenosi si� do Gdyni z dniem 1 kwietnia
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
-- ZALETA: nie wymaga przemapowywania kluczy biznesowych na hurtowniane w tabeli fakt�w
--         jeden wiersz tabeli wymiaru odpowiada nadal jednemu elementowi danych (tu: klientowi)
-- WADA: dodatkowa jedna kolumna na ka�d� zmian� ka�dego atrybutu
--       bez zmiany tre�ci zapytania raportowego, dane b�d� si� "przenosi�" (czasem jest to zaleta...)

-- inne, bardziej z�o�one typy SCD opisane s� tutaj:
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

