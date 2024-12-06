CREATE TABLE Cities(
	CityID SERIAL PRIMARY KEY,
	Name VARCHAR(50) NOT NULL UNIQUE
)

CREATE TABLE Restaurants(
    RestaurantID SERIAL PRIMARY KEY,
    Name VARCHAR(50) NOT NULL,
    CityID INT REFERENCES Cities(CityID),
    Capacity INT NOT NULL CHECK (Capacity > 0),
    OpeningTime TIME NOT NULL,
    ClosingTime TIME NOT NULL,
    CONSTRAINT CheckTimes CHECK (OpeningTime < ClosingTime),
	UNIQUE (Name,CityID)
);

CREATE TABLE DishCategories(
    CategoryID SERIAL PRIMARY KEY,
    Name VARCHAR(30) NOT NULL UNIQUE
);

INSERT INTO DishCategories(Name) VALUES
('Appetizer'),
('Main Course'),
('Dessert');

CREATE TABLE Dishes(
    DishID SERIAL PRIMARY KEY,
    Name VARCHAR(50) NOT NULL,
    Description TEXT,
    CategoryID INT REFERENCES DishCategories(CategoryID) NOT NULL,
    Calories FLOAT CHECK (Calories > 0)
);

CREATE TABLE RestaurantDish(
    RestaurantID INT REFERENCES Restaurants(RestaurantID),
    DishID INT REFERENCES Dishes(DishID),
    Price DECIMAL(10,2) NOT NULL CHECK (Price > 0),
	IsAvailable BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (RestaurantID, DishID)
);

CREATE TABLE Users(
    UserID SERIAL PRIMARY KEY,
    Name VARCHAR(30) NOT NULL,
	Surname VARCHAR(30) NOT NULL,
    Email VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE Orders(
    OrderID SERIAL PRIMARY KEY,
    UserID INT REFERENCES Users(UserID),
    RestaurantID INT REFERENCES Restaurants(RestaurantID),
    OrderType VARCHAR(20) NOT NULL CHECK (OrderType IN ('Delivery','Dine-In')),
    DeliveryAddress VARCHAR(100),
    TotalAmount DECIMAL(10, 2) NOT NULL DEFAULT 0,
    OrderDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	CONSTRAINT check_delivery_address_validity CHECK (
        (OrderType = 'Delivery' AND DeliveryAddress IS NOT NULL) OR
        (OrderType = 'Dine-In' AND DeliveryAddress IS NULL)
    )
);

CREATE TABLE OrderDetails(
    OrderDetailID SERIAL PRIMARY KEY,
    OrderID INT REFERENCES Orders(OrderID),
    RestaurantID INT NOT NULL,
    DishID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    Price DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (RestaurantID, DishID) REFERENCES RestaurantDish(RestaurantID, DishID)
);

CREATE TABLE Staff(
    StaffID SERIAL PRIMARY KEY,
    RestaurantID INT REFERENCES Restaurants(RestaurantID),
    Name VARCHAR(30) NOT NULL,
	Surname VARCHAR(30) NOT NULL,
    Role VARCHAR(50) NOT NULL CHECK (Role IN ('Chef', 'Waiter', 'Delivery Person')),
    BirthDate DATE NOT NULL,
    HasDrivingLicense BOOLEAN,
    UNIQUE (Name,Surname,BirthDate)
);

ALTER TABLE Staff
ADD CONSTRAINT check_min_age_for_chef
CHECK (Role != 'Chef' OR EXTRACT(YEAR FROM age(BirthDate)) >= 18);

ALTER TABLE Staff
ADD CONSTRAINT check_driving_license_for_delivery_person
CHECK (Role != 'Delivery Person' OR (HasDrivingLicense IS NOT NULL AND HasDrivingLicense = TRUE));

CREATE TABLE Deliveries(
    DeliveryID SERIAL PRIMARY KEY,
    OrderID INT REFERENCES Orders(OrderID),
    StaffID INT NOT NULL REFERENCES Staff(StaffID),
    DeliveryTime TIME NOT NULL,
    UserNote TEXT
);

CREATE TABLE Reviews(
    ReviewID SERIAL PRIMARY KEY,
    OrderID INT REFERENCES Orders(OrderID),
    DeliveryID INT REFERENCES Deliveries(DeliveryID),
    OrderRating INT CHECK (OrderRating >= 1 AND OrderRating <= 5),
    DeliveryRating INT CHECK (DeliveryRating >= 1 AND DeliveryRating <= 5),
    Comment TEXT,
    ReviewDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	UNIQUE(OrderID,DeliveryID),
    CONSTRAINT check_valid_ratings CHECK (
        (OrderID IS NOT NULL AND OrderRating IS NOT NULL) OR (DeliveryID IS NOT NULL AND DeliveryRating IS NOT NULL)
    )
);

CREATE TABLE LoyaltyCards(
    CardID SERIAL PRIMARY KEY,
    UserID INT REFERENCES Users(UserID) UNIQUE,
    IssueDate DATE NOT NULL DEFAULT CURRENT_DATE
);

--TRIGGERS

CREATE OR REPLACE FUNCTION validate_delivery()
RETURNS TRIGGER AS $$
DECLARE
    staff_restaurant_id INT;
    order_restaurant_id INT;
    order_type VARCHAR(20);
    staff_role VARCHAR(50);
BEGIN
    SELECT RestaurantID, Role INTO staff_restaurant_id, staff_role
    FROM Staff
    WHERE StaffID = NEW.StaffID;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Staff member does not exist.';
    END IF;

    IF staff_role != 'Delivery Person' THEN
        RAISE EXCEPTION 'Staff member is not a delivery person.';
    END IF;

    SELECT RestaurantID, OrderType INTO order_restaurant_id, order_type
    FROM Orders
    WHERE OrderID = NEW.OrderID;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order does not exist.';
    END IF;

    IF order_type != 'Delivery' THEN
        RAISE EXCEPTION 'Order is not for delivery.';
    END IF;

    IF staff_restaurant_id != order_restaurant_id THEN
        RAISE EXCEPTION 'Delivery person does not belong to the same restaurant as the order.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_delivery_insert
BEFORE INSERT ON Deliveries
FOR EACH ROW
EXECUTE FUNCTION validate_delivery();



CREATE OR REPLACE FUNCTION validate_and_set_price()
RETURNS TRIGGER AS $$
DECLARE
    dish_price DECIMAL(10, 2);
    is_available BOOLEAN;
    order_restaurant_id INT;
BEGIN
    SELECT Price, IsAvailable INTO dish_price, is_available
    FROM RestaurantDish
    WHERE RestaurantID = NEW.RestaurantID AND DishID = NEW.DishID;

    IF NOT FOUND OR is_available = FALSE THEN
        RAISE EXCEPTION 'Dish is not available in this restaurant.';
    END IF;

    SELECT RestaurantID INTO order_restaurant_id
    FROM Orders
    WHERE OrderID = NEW.OrderID;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order does not exist.';
    END IF;

    IF NEW.RestaurantID != order_restaurant_id THEN
        RAISE EXCEPTION 'RestaurantID in OrderDetails does not match the RestaurantID of the order.';
    END IF;

    NEW.Price = dish_price;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_dish_availability_and_price
BEFORE INSERT ON OrderDetails
FOR EACH ROW
EXECUTE FUNCTION validate_and_set_price();



CREATE OR REPLACE FUNCTION update_total_amount()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Orders
    SET TotalAmount = (
        SELECT SUM(od.Price * od.Quantity)
        FROM OrderDetails od
        WHERE od.OrderID = NEW.OrderID
    )
    WHERE OrderID = NEW.OrderID;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_total_amount
AFTER INSERT OR UPDATE OR DELETE ON OrderDetails
FOR EACH ROW
EXECUTE FUNCTION update_total_amount();



CREATE OR REPLACE FUNCTION check_and_issue_loyalty_card()
RETURNS TRIGGER AS $$
DECLARE
    order_count INT;
    total_amount DECIMAL(10, 2);
    card_exists INT;
BEGIN
    SELECT COUNT(*) INTO card_exists
    FROM LoyaltyCards
    WHERE UserID = NEW.UserID;

    IF card_exists = 0 THEN
        SELECT COUNT(*), SUM(TotalAmount) INTO order_count, total_amount
        FROM Orders
        WHERE UserID = NEW.UserID;

        IF order_count > 15 AND total_amount > 1000 THEN
            INSERT INTO LoyaltyCards(UserID) VALUES (NEW.UserID);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_order_insert
AFTER INSERT ON Orders
FOR EACH ROW
EXECUTE FUNCTION check_and_issue_loyalty_card();






