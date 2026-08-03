package state

import (
	"net/netip"
	"sync"
)

var DefaultIpv4Address = "172.19.0.1/30"
var DefaultDnsAddress = "172.19.0.2"
var DefaultIpv6Address = "fdfe:dcba:9876::1/126"

type AndroidVpnOptions struct {
	Enable           bool           `json:"enable"`
	Port             int            `json:"port"`
	AccessControl    *AccessControl `json:"accessControl"`
	AllowBypass      bool           `json:"allowBypass"`
	SystemProxy      bool           `json:"systemProxy"`
	BypassDomain     []string       `json:"bypassDomain"`
	RouteAddress     []netip.Prefix `json:"routeAddress"`
	Ipv4Address      string         `json:"ipv4Address"`
	Ipv6Address      string         `json:"ipv6Address"`
	DnsServerAddress string         `json:"dnsServerAddress"`
}

type AccessControl struct {
	Enable            bool     `json:"enable"`
	Mode              string   `json:"mode"`
	AcceptList        []string `json:"acceptList"`
	RejectList        []string `json:"rejectList"`
}

type AndroidVpnRawOptions struct {
	Enable        bool           `json:"enable"`
	AccessControl *AccessControl `json:"accessControl"`
	AllowBypass   bool           `json:"allowBypass"`
	SystemProxy   bool           `json:"systemProxy"`
	Ipv6          bool           `json:"ipv6"`
}

type State struct {
	VpnProps            AndroidVpnRawOptions `json:"vpn-props"`
	CurrentProfileName  string               `json:"current-profile-name"`
	OnlyStatisticsProxy bool                 `json:"only-statistics-proxy"`
	BypassDomain        []string             `json:"bypass-domain"`
}

// stateMu guards the CurrentState pointer only. The State value it points to is
// never mutated in place after publication; SetCurrentState swaps the whole
// pointer under the write lock, and readers take ONE snapshot via
// GetCurrentState() so concurrent traffic/tun readers can't race the swap.
var (
	stateMu      sync.RWMutex
	CurrentState = &State{
		OnlyStatisticsProxy: false,
		CurrentProfileName:  "",
	}
)

// GetCurrentState returns the current shared state pointer under a read lock.
// Callers must snapshot once per operation and read fields off the returned
// pointer, not re-call for each field.
func GetCurrentState() *State {
	stateMu.RLock()
	defer stateMu.RUnlock()
	return CurrentState
}

// SetCurrentState atomically publishes a new shared state pointer under the
// write lock. A nil argument is ignored to preserve the never-nil invariant.
func SetCurrentState(next *State) {
	if next == nil {
		return
	}
	stateMu.Lock()
	defer stateMu.Unlock()
	CurrentState = next
}

func GetIpv6Address() string {
	if GetCurrentState().VpnProps.Ipv6 {
		return DefaultIpv6Address
	} else {
		return ""
	}
}

func GetDnsServerAddress() string {
	return DefaultDnsAddress
}
