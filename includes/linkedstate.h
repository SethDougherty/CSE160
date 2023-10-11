#ifndef LINKEDSTATE_H
#define LINKEDSTATE_H

typedef struct Route{
        uint8_t nextHop;
        uint8_t cost;
        uint8_t neighbor;
    } Route;

    typedef struct LSP{
        uint8_t neighbor;
        uint8_t cost;
    } LSP;

#endif