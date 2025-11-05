local sha256 = {}

local function to_hex(num)
    return string.format("%08x", num)
end

local function right_rotate(x, n)
    return bit.bor(bit.brshift(x, n), bit.blshift(x, 32 - n))
end

local function ch(x, y, z)
    return bit.bxor(bit.band(x, y), bit.band(bit.bnot(x), z))
end

local function maj(x, y, z)
    return bit.bxor(bit.band(x, y), bit.band(x, z), bit.band(y, z))
end

local function sigma0(x)
    return bit.bxor(right_rotate(x, 2), right_rotate(x, 13), right_rotate(x, 22))
end

local function sigma1(x)
    return bit.bxor(right_rotate(x, 6), right_rotate(x, 11), right_rotate(x, 25))
end

local function gamma0(x)
    return bit.bxor(right_rotate(x, 7), right_rotate(x, 18), bit.brshift(x, 3))
end

local function gamma1(x)
    return bit.bxor(right_rotate(x, 17), right_rotate(x, 19), bit.brshift(x, 10))
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

function sha256.hex(msg)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }
    local msg_len_bits = #msg * 8
    msg = msg .. "\128"
    while (#msg % 64) ~= 56 do
        msg = msg .. "\0"
    end
    msg = msg .. string.pack(">I8", 0, msg_len_bits)
    
    for i = 1, #msg, 64 do
        local chunk = msg:sub(i, i + 63)
        local W = {}
        for j = 0, 15 do
            W[j] = string.unpack(">I4", chunk, j * 4 + 1)
        end
        for j = 16, 63 do
            local s0 = gamma0(W[j-15])
            local s1 = gamma1(W[j-2])
            W[j] = (W[j-16] + s0 + W[j-7] + s1) % 2^32
        end
        
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        
        for j = 0, 63 do
            local S1 = sigma1(e)
            local ch_val = ch(e, f, g)
            local temp1 = (h + S1 + ch_val + K[j+1] + W[j]) % 2^32
            local S0 = sigma0(a)
            local maj_val = maj(a, b, c)
            local temp2 = (S0 + maj_val) % 2^32
            h, g, f, e, d, c, b, a = g, f, e, (d + temp1) % 2^32, c, b, a, (temp1 + temp2) % 2^32
        end
        
        H[1] = (H[1] + a) % 2^32
        H[2] = (H[2] + b) % 2^32
        H[3] = (H[3] + c) % 2^32
        H[4] = (H[4] + d) % 2^32
        H[5] = (H[5] + e) % 2^32
        H[6] = (H[6] + f) % 2^32
        H[7] = (H[7] + g) % 2^32
        H[8] = (H[8] + h) % 2^32
    end
    
    local result = ""
    for i = 1, 8 do
        result = result .. to_hex(H[i])
    end
    return result
end

return sha256