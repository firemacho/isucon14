package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"sync"
)

type cacheSliceUser struct {
	// Setが多いならsync.Mutex
	sync.RWMutex
	items map[string]*User
}
func NewcacheSliceUser() *cacheSliceUser {
	m := make(map[string]*User)
	c := &cacheSliceUser{
		items: m,
	}
	return c
}
func (c *cacheSliceUser) Set(key string, value *User) {
	c.Lock()
	c.items[key] = value
	c.Unlock()
}
func (c *cacheSliceUser) Get(key string) (*User, bool) {
	c.RLock()
	v, found := c.items[key]
	c.RUnlock()
	return v, found
}
func (c *cacheSliceUser) Clear() {
	c.Lock()
	c.items = make(map[string]*User) // 空のマップに置き換え
	c.Unlock()
}
var userCache = NewcacheSliceUser()

type cacheSliceChair struct {
	// Setが多いならsync.Mutex
	sync.RWMutex
	items map[string]*Chair
}
func NewcacheSliceChair() *cacheSliceChair {
	m := make(map[string]*Chair)
	c := &cacheSliceChair{
		items: m,
	}
	return c
}
func (c *cacheSliceChair) Set(key string, value *Chair) {
	c.Lock()
	c.items[key] = value
	c.Unlock()
}
func (c *cacheSliceChair) Get(key string) (*Chair, bool) {
	c.RLock()
	v, found := c.items[key]
	c.RUnlock()
	return v, found
}
func (c *cacheSliceChair) Clear() {
	c.Lock()
	c.items = make(map[string]*Chair) // 空のマップに置き換え
	c.Unlock()
}
var chairCache = NewcacheSliceChair()

func appAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		c, err := r.Cookie("app_session")
		if errors.Is(err, http.ErrNoCookie) || c.Value == "" {
			writeError(w, http.StatusUnauthorized, errors.New("app_session cookie is required"))
			return
		}
		accessToken := c.Value

		// キャッシュから取得
        var user *User
        cachedUser, ok := userCache.Get(accessToken)
        if ok {
            user = cachedUser
        } else {
            user = &User{}
            err := db.GetContext(ctx, user, "SELECT * FROM users WHERE access_token = ?", accessToken)
            if err != nil {
                if errors.Is(err, sql.ErrNoRows) {
                    writeError(w, http.StatusUnauthorized, errors.New("invalid access token"))
                    return
                }
                writeError(w, http.StatusInternalServerError, err)
                return
            }
            userCache.Set(accessToken, user)
        }

		ctx = context.WithValue(ctx, "user", user)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func ownerAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		c, err := r.Cookie("owner_session")
		if errors.Is(err, http.ErrNoCookie) || c.Value == "" {
			writeError(w, http.StatusUnauthorized, errors.New("owner_session cookie is required"))
			return
		}
		accessToken := c.Value
		owner := &Owner{}
		if err := db.GetContext(ctx, owner, "SELECT * FROM owners WHERE access_token = ?", accessToken); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				writeError(w, http.StatusUnauthorized, errors.New("invalid access token"))
				return
			}
			writeError(w, http.StatusInternalServerError, err)
			return
		}

		ctx = context.WithValue(ctx, "owner", owner)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func chairAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		c, err := r.Cookie("chair_session")
		if errors.Is(err, http.ErrNoCookie) || c.Value == "" {
			writeError(w, http.StatusUnauthorized, errors.New("chair_session cookie is required"))
			return
		}
		accessToken := c.Value

		// キャッシュから取得
        var chair *Chair
        cachedChair, ok := chairCache.Get(accessToken)
        if ok {
            chair = cachedChair
        } else {
            chair = &Chair{}
            err := db.GetContext(ctx, chair, "SELECT * FROM chairs WHERE access_token = ?", accessToken)
            if err != nil {
                if errors.Is(err, sql.ErrNoRows) {
                    writeError(w, http.StatusUnauthorized, errors.New("invalid access token"))
                    return
                }
                writeError(w, http.StatusInternalServerError, err)
                return
            }
            chairCache.Set(accessToken, chair)
        }

		ctx = context.WithValue(ctx, "chair", chair)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
