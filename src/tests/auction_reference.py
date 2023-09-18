# Define the bids
bids = [
    {"id": 1, "size": 2, "price": 20},
    {"id": 2, "size": 4, "price": 11},
    {"id": 3, "size": 5, "price": 11},
    {"id": 4, "size": 3, "price": 2},
    {"id": 5, "size": 7, "price": 0.5},
    {"id": 6, "size": 5, "price": 0.3},
]

# Sort bids by price from highest to lowest
# If there are bids with the same price, sort them from low bid amount to high bid amount
bids = sorted(bids, key=lambda x: (-x['price'], x['size']))

pile = 15  # total number of tokens

def distribute_tokens(pile, bids):
    for i in range(len(bids)):
        total_distributed = 0
        for j in range(i + 1):
            bid = bids[j]
            total_distributed += min(bid['size'], bid['size'] / bids[i]['price'])
        if total_distributed >= pile:
            return i
    return -1

idx = distribute_tokens(pile, bids)

if idx != -1:
    print(f"Clearing price of the auction is {bids[idx]['price']}")
    
    tokens_left = pile
    for i in range(idx + 1):
        bid = bids[i]
        tokens_to_give = min(tokens_left, bid['size'] / bids[idx]['price'])
        tokens_left -= tokens_to_give
        print(f"Bidder {bid['id']} gets {tokens_to_give:.2f} tokens")
        
    for i in range(idx + 1, len(bids)):
        bid = bids[i]
        print(f"Bidder {bid['id']} doesn't get any tokens (and full bidding token refund)")
else:
    print("All tokens could not be distributed using these bids.")
