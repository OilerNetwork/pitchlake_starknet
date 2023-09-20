


print ("########################################################################################")
print ("SIZE IS OPTION COUNT")

# Define the bids, size of the bid as in number of options, and the price of the bid as in the price per option
bids = [
    {"id": 1, "size": 2000, "price": 8},
    {"id": 2, "size": 5000, "price": 5},
    {"id": 3, "size": 5000, "price": 2},
    {"id": 4, "size": 10000, "price": 10},
    {"id": 5, "size": 500, "price": 3},
     {"id": 6, "size": 5, "price": 22},
]

RESERVE_PRICE = 9

# Filter out bids below reserve price and print them
removed_bids = [bid for bid in bids if bid['price'] < RESERVE_PRICE]
bids = [bid for bid in bids if bid['price'] >= RESERVE_PRICE]

for bid in removed_bids:
    print(f"Bidder {bid['id']} with bid price {bid['price']} has been removed due to the reserve price of {RESERVE_PRICE}.")


# Sort bids by price from highest to lowest
# If there are bids with the same price, sort them from low bid amount to high bid amount and then the bid id(signifying the time of the bid, from earliest to latest)
bids = sorted(bids, key=lambda x: (-x['price'], x['size'], x['id']))

options_available = 12500  # total number of options available

def distribute_options(options_available, bids):
    total_distributed = 0
    for i in range(len(bids)):
        # for j in range(i + 1):
        bid = bids[i]
            # total_distributed += min(bid['size'], bid['size'] * bids[i]['price'] / bid['price'])
        total_distributed += bid['size']
        if total_distributed >= options_available:
            return i  # this is the clearing bid
    return len(bids) - 1  # if not all options can be sold, the last bid's price is the clearing price

idx = distribute_options(options_available, bids)

print(f"Clearing price of the auction is {bids[idx]['price']}")

options_left = options_available
for i in range(idx + 1):
    bid = bids[i]
    options_to_give = min(options_left, bid['size'])
    options_left -= options_to_give
    print(f"Bidder {bid['id']} gets {options_to_give:.2f} options")
    
for i in range(idx + 1, len(bids)):
    bid = bids[i]
    print(f"Bidder {bid['id']} doesn't get any options (and full bidding token refund)")

if options_left > 0:
    print(f"{options_left:.2f} options remain undistributed.")
