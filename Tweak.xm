#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ===================================================================
// 完整结构体定义（解决 incomplete type 错误）
// ===================================================================
struct SBHIconGridSize {
    unsigned short columns;
    unsigned short rows;
};

struct SBHIconGridRange {
    unsigned long long location;
    struct SBHIconGridSize size;
};

// ===================================================================
// 1. 接口声明
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
- (NSString *)nodeIdentifier;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
- (BOOL)allowsGaps;
@end

@interface SBIconListModel : NSObject
- (NSString *)uniqueIdentifier;
- (unsigned long long)maxNumberOfIcons;
- (NSArray *)icons;
- (id)iconAtIndex:(unsigned long long)index;
- (unsigned long long)indexForIcon:(id)icon;
- (BOOL)allowsFixedIconLocations;
- (long long)fixedIconLocationBehavior;
- (BOOL)isIconFixed:(id)icon;
- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options;
- (unsigned long long)fixedLocationForIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon options:(unsigned long long)options;
- (void)removeAllFixedIconLocations;
- (void)removeFixedIconLocationForIcon:(id)icon;
- (void)removeFixedIconLocationsForIcons:(id)icons;
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info;
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options;
- (id)_updateModelByRepairingGapsIfNecessary;
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons;
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding;
- (BOOL)isGridLayoutValid;
- (BOOL)isGridLayoutValid:(id)info;
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options;
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons;
- (BOOL)canUseFastGridLayoutValidity;
- (BOOL)requiresSomeFixedIconLocations;
- (void)setIcons:(NSArray *)icons;
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options;
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (id)setIconsFromIconListModel:(id)model;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options;
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info;
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options;
- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options;
- (void)removeIcon:(id)icon;
- (void)removeIcon:(id)icon options:(unsigned long long)options;
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions;
- (void)removeIconAtIndex:(unsigned long long)index;
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options;
@end

// ===================================================================
// 2. 坐标管理引擎（rootless / roothide 友好）
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.freegrid.layout.plist"

static NSMutableDictionary *gGridConfig = nil;
static dispatch_queue_t gSaveQueue;

static void EnsureSaveQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.freegrid.layout.save", DISPATCH_QUEUE_SERIAL);
    });
}

static void LoadGridConfig(void) {
    if (gGridConfig) return;
    @try {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        gGridConfig = dict ? [dict mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused NSException *e) {
        gGridConfig = [NSMutableDictionary new];
    }
}

static void SaveGridConfig(void) {
    if (!gGridConfig) return;
    EnsureSaveQueue();
    NSDictionary *snapshot = [gGridConfig copy];
    dispatch_async(gSaveQueue, ^{
        @try {
            [snapshot writeToFile:PLIST_PATH atomically:YES];
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0666}
                                             ofItemAtPath:PLIST_PATH
                                                    error:nil];
        } @catch (__unused NSException *e) {}
    });
}

static NSString *GetIconID(id icon) {
    if (!icon) return nil;
    if ([icon respondsToSelector:@selector(leafIdentifier)]) {
        NSString *leaf = [icon leafIdentifier];
        if (leaf.length > 0) return leaf;
    }
    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        NSString *bid = [icon applicationBundleIdentifier];
        if (bid.length > 0) return bid;
    }
    if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
        NSString *node = [icon nodeIdentifier];
        if (node.length > 0) return node;
    }
    return [NSString stringWithFormat:@"%p", icon];
}

static void ApplyFixedLocationsFromPlist(SBIconListModel *model) {
    if (!model) return;
    NSString *listID = [model uniqueIdentifier];
    if (!listID.length) return;

    LoadGridConfig();
    NSDictionary *listConfig = gGridConfig[listID];
    if (!listConfig.count) return;

    NSArray *icons = [model icons];
    if (!icons.count) return;

    unsigned long long max = [model maxNumberOfIcons];
    for (id icon in icons) {
        NSString *iconID = GetIconID(icon);
        if (!iconID) continue;
        NSNumber *num = listConfig[iconID];
        if (!num) continue;
        unsigned long long loc = [num unsignedLongLongValue];
        if (loc >= max) continue;
        if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [model setFixedLocation:loc forIcon:icon options:0];
        } else {
            [model setFixedLocation:loc forIcon:icon];
        }
    }
}

static BOOL IsDockList(SBIconListModel *model) {
    return NO; // Dock 由 View 层 allowsGaps 保护
}

// 提前声明，解决 undeclared identifier
static void CleanupIconFromPlist(SBIconListModel *model, id icon);

static void CleanupIconFromPlist(SBIconListModel *model, id icon) {
    if (!model || !icon) return;
    NSString *listID = [model uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return;
    LoadGridConfig();
    NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
    if (listConfig && listConfig[iconID]) {
        [listConfig removeObjectForKey:iconID];
        if (listConfig.count == 0) {
            [gGridConfig removeObjectForKey:listID];
        } else {
            gGridConfig[listID] = listConfig;
        }
        SaveGridConfig();
    }
}

// ===================================================================
// 3. 视图层
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        if (location && ([location containsString:@"Dock"] || [location containsString:@"dock"])) {
            return %orig;
        }
    }
    return YES;
}

%end

// ===================================================================
// 4. 数据层（完整防御）
// ===================================================================
%hook SBIconListModel

- (BOOL)allowsFixedIconLocations {
    return YES;
}

- (long long)fixedIconLocationBehavior {
    return 1;
}

- (BOOL)requiresSomeFixedIconLocations {
    return YES;
}

- (BOOL)isIconFixed:(id)icon {
    if (!icon || IsDockList(self)) return %orig;
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (listID && iconID) {
        LoadGridConfig();
        NSDictionary *cfg = gGridConfig[listID];
        if (cfg && cfg[iconID]) return YES;
    }
    return YES; // 强制所有图标视为 Fixed，彻底禁止自动排序
}

- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options {
    return [self isIconFixed:icon];
}

- (unsigned long long)fixedLocationForIcon:(id)icon {
    if (!icon || IsDockList(self)) return %orig;
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (listID && iconID) {
        LoadGridConfig();
        NSDictionary *cfg = gGridConfig[listID];
        if (cfg && cfg[iconID]) {
            unsigned long long loc = [cfg[iconID] unsignedLongLongValue];
            if (loc < [self maxNumberOfIcons]) return loc;
        }
    }
    unsigned long long idx = [self indexForIcon:icon];
    if (idx != NSNotFound) return idx;
    return %orig;
}

- (void)removeAllFixedIconLocations {
}

- (void)removeFixedIconLocationForIcon:(id)icon {
}

- (void)removeFixedIconLocationsForIcons:(id)icons {
}

- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info {
}

- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options {
}

- (id)_updateModelByRepairingGapsIfNecessary {
    return nil;
}

- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return nil;
}

- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding {
    return icons;
}

- (BOOL)isGridLayoutValid {
    return YES;
}

- (BOOL)isGridLayoutValid:(id)info {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options {
    return YES;
}

- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons {
    if (outIcons) *outIcons = nil;
    return YES;
}

- (BOOL)canUseFastGridLayoutValidity {
    return NO;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    if (index != NSNotFound && index < [self maxNumberOfIcons]) return index;
    return %orig;
}

- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    if (!icon || index == NSNotFound || IsDockList(self)) return result;

    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (listID && iconID && index < [self maxNumberOfIcons]) {
        if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [self setFixedLocation:index forIcon:icon options:0];
        } else {
            [self setFixedLocation:index forIcon:icon];
        }
        LoadGridConfig();
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        SaveGridConfig();
    }
    return result;
}

- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    id result = %orig;
    if (!icon || IsDockList(self)) return result;
    unsigned long long gridIdx = [self fixedLocationForIcon:icon];
    if (gridIdx != NSNotFound && gridIdx < [self maxNumberOfIcons]) {
        NSString *listID = [self uniqueIdentifier];
        NSString *iconID = GetIconID(icon);
        if (listID && iconID) {
            if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
                [self setFixedLocation:gridIdx forIcon:icon options:0];
            }
            LoadGridConfig();
            NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
            listConfig[iconID] = @(gridIdx);
            gGridConfig[listID] = listConfig;
            SaveGridConfig();
        }
    }
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    if (!icon || index == NSNotFound || IsDockList(self)) return result;

    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (listID && iconID && index < [self maxNumberOfIcons]) {
        if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
            [self setFixedLocation:index forIcon:icon options:0];
        } else {
            [self setFixedLocation:index forIcon:icon];
        }
        LoadGridConfig();
        NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
        listConfig[iconID] = @(index);
        gGridConfig[listID] = listConfig;
        SaveGridConfig();
    }
    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    %orig;
    if (!icon || IsDockList(self)) return;
    unsigned long long gridIdx = [self fixedLocationForIcon:icon];
    if (gridIdx != NSNotFound && gridIdx < [self maxNumberOfIcons]) {
        NSString *listID = [self uniqueIdentifier];
        NSString *iconID = GetIconID(icon);
        if (listID && iconID) {
            if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
                [self setFixedLocation:gridIdx forIcon:icon options:0];
            }
            LoadGridConfig();
            NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
            listConfig[iconID] = @(gridIdx);
            gGridConfig[listID] = listConfig;
            SaveGridConfig();
        }
    }
}

- (void)removeIcon:(id)icon {
    %orig;
    CleanupIconFromPlist(self, icon);
}

- (void)removeIcon:(id)icon options:(unsigned long long)options {
    %orig;
    CleanupIconFromPlist(self, icon);
}

- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    %orig;
    CleanupIconFromPlist(self, icon);
}

- (void)removeIconAtIndex:(unsigned long long)index {
    id icon = (index < [self maxNumberOfIcons]) ? [self iconAtIndex:index] : nil;
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}

- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options {
    id icon = (index < [self maxNumberOfIcons]) ? [self iconAtIndex:index] : nil;
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}

- (void)setIcons:(NSArray *)icons {
    %orig;
    ApplyFixedLocationsFromPlist(self);
}

- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}

- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}

- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    ApplyFixedLocationsFromPlist(self);
    return result;
}

%end
