# Define the bids
# id is used to order the bids
# num_units is the total num of options that the bid wants to buy
# pice is the price of one call option
# ## The total amount of money in a bid is given by num_units * price

# options_available = 200 # total number of options available
# bids = [
#     {"id": 1, "num_units": 50, "price": 20},
#     {"id": 2, "num_units": 142, "price": 11},
#     {"id": 3, "num_units": 235, "price": 11},
#     {"id": 4, "num_units": 222, "price": 2},
#     {"id": 5, "num_units": 75, "price": 1},
#     {"id": 6, "num_units": 35, "price": 1},
# ]

# options_available = 200
# bids = [
#     {"id": 1, "num_units": 25, "price": 25},
#     {"id": 2, "num_units": 20, "price": 24},
#     {"id": 3, "num_units": 60, "price": 15},
#     {"id": 4, "num_units": 40, "price": 2},
#     {"id": 5, "num_units": 75, "price": 1},
#     {"id": 6, "num_units": 35, "price": 1},
# ]

options_available = 500
bids = [
     {"id": 1, "num_units": 400, "price": 50},
     {"id": 2, "num_units": 50, "price": 40},
     {"id": 3, "num_units": 30, "price": 30},
     {"id": 4, "num_units": 50, "price": 20},
     {"id": 5, "num_units": 75, "price": 2},
     {"id": 6, "num_units": 35, "price": 2},
]

RESERVE_PRICE = 2

# Filter out bids below reserve price and print them
removed_bids = [bid for bid in bids if bid['price'] < RESERVE_PRICE]
bids = [bid for bid in bids if bid['price'] >= RESERVE_PRICE]

for bid in removed_bids:
    print(f"Bidder {bid['id']} with bid price {bid['price']} has been removed due to the reserve price of {RESERVE_PRICE}.")
print()

# Sort bids by price from highest to lowest
# If there are bids with the same price, sort them from low bid amount to high bid amount and then the bid id(signifying the time of the bid, from earliest to latest)
bids = sorted(bids, key=lambda x: (-x['price'], x['num_units'], x['id']))


def distribute_options(options_available, bids):
    total_distributed = 0
    for i in range(len(bids)):
        # for j in range(i + 1):
        bid = bids[i]
            # total_distributed += min(bid['num_units'], bid['num_units'] * bids[i]['price'] / bid['price'])
        total_distributed += bid['num_units']
        if total_distributed >= options_available:
            return i  # this is the clearing bid
    return len(bids) - 1  # if not all options can be sold, the last bid's price is the clearing price

idx = distribute_options(options_available, bids)

print(f"Clearing price of the auction is {bids[idx]['price']}")
print()

options_left = options_available
for i in range(idx + 1):
    bid = bids[i]
    options_to_give = min(options_left, bid['num_units'])
    options_left -= options_to_give
    print(f"Bidder {bid['id']} gets {options_to_give:.2f} options")

for i in range(idx + 1, len(bids)):
    bid = bids[i]
    print(f"Bidder {bid['id']} doesn't get any options (and full bidding token refund)")

if options_left > 0:
    print(f"{options_left:.2f} options remain undistributed.")
