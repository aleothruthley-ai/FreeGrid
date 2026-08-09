#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ===================================================================
// 结构体定义
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
// 接口声明
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
- (NSString *)nodeIdentifier;
- (id)folder;
@end

@interface SBFolder : NSObject
- (NSString *)uniqueIdentifier;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
- (BOOL)allowsGaps;
- (id)model;
- (void)layoutIconsNow;
- (void)setIconsNeedLayout;
@end

@interface SBIconListModel : NSObject
- (NSString *)uniqueIdentifier;
- (unsigned long long)maxNumberOfIcons;
- (NSArray *)icons;
- (id)iconAtIndex:(unsigned long long)index;
- (unsigned long long)indexForIcon:(id)icon;
- (unsigned long long)gridCellIndexForIcon:(id)icon gridCellInfoOptions:(unsigned long long)options;
- (BOOL)allowsFixedIconLocations;
- (long long)fixedIconLocationBehavior;
- (BOOL)isIconFixed:(id)icon;
- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options;
- (unsigned long long)fixedLocationForIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon options:(unsigned long long)options;
- (void)saveCurrentIconLocationsAsFixed;
- (void)saveOnlyRequiredIconLocationsAsFixed;
- (void)saveOnlyRequiredIconLocationsAsFixedIfRequired;
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

@interface SBHIconManager : NSObject
- (long long)listsFixedIconLocationBehavior;
- (long long)listsFixedIconLocationBehaviorForFolderClass:(Class)cls;
- (long long)iconModel:(id)model listsFixedIconLocationBehaviorForFolderClass:(Class)cls;
- (void)ensureFixedIconLocationsIfNecessary;
@end

// ===================================================================
// 坐标管理引擎（只记录用户移动过的图标）- iOS 17 稳定版
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.iosdump.freegrid.plist"

static NSMutableDictionary *gGridConfig = nil;
static dispatch_queue_t gSaveQueue;
static NSLock *gConfigLock = nil;

static void EnsureInfrastructure(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSaveQueue = dispatch_queue_create("com.iosdump.freegrid.save", DISPATCH_QUEUE_SERIAL);
        gConfigLock = [[NSLock alloc] init];
    });
}

static void LoadGridConfig(void) {
    EnsureInfrastructure();
    [gConfigLock lock];
    if (gGridConfig) {
        [gConfigLock unlock];
        return;
    }
    @try {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:PLIST_PATH];
        gGridConfig = dict ? [dict mutableCopy] : [NSMutableDictionary new];
    } @catch (__unused NSException *e) {
        gGridConfig = [NSMutableDictionary new];
    }
    [gConfigLock unlock];
}

static void SaveGridConfig(void) {
    EnsureInfrastructure();
    [gConfigLock lock];
    if (!gGridConfig) {
        [gConfigLock unlock];
        return;
    }
    NSDictionary *snapshot = [gGridConfig copy];
    [gConfigLock unlock];

    dispatch_async(gSaveQueue, ^{
        @try {
            [snapshot writeToFile:PLIST_PATH atomically:YES];
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions : @0666}
                                             ofItemAtPath:PLIST_PATH
                                                    error:nil];
        } @catch (__unused NSException *e) {}
    });
}

// 更稳定的 Icon ID（优先 leaf / bundle，尽量避免指针）
static NSString *GetIconID(id icon) {
    if (!icon) return nil;

    Class folderIconClass = NSClassFromString(@"SBFolderIcon");
    if (folderIconClass && [icon isKindOfClass:folderIconClass]) {
        if ([icon respondsToSelector:@selector(folder)]) {
            id folder = [icon folder];
            if (folder && [folder respondsToSelector:@selector(uniqueIdentifier)]) {
                NSString *fid = [folder uniqueIdentifier];
                if (fid.length > 0) {
                    return [@"folder:" stringByAppendingString:fid];
                }
            }
        }
        if ([icon respondsToSelector:@selector(nodeIdentifier)]) {
            NSString *node = [icon nodeIdentifier];
            if (node.length > 0) {
                return [@"folder-node:" stringByAppendingString:node];
            }
        }
        if ([icon respondsToSelector:@selector(leafIdentifier)]) {
            NSString *leaf = [icon leafIdentifier];
            if (leaf.length > 0) {
                return [@"folder-leaf:" stringByAppendingString:leaf];
            }
        }
        // 最后兜底，尽量少用
        return [NSString stringWithFormat:@"folder-%p", icon];
    }

    // 普通图标优先 leafIdentifier（最稳定）
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

static BOOL IsDockList(SBIconListModel *model) {
    // 如有需要可扩展：通过 iconLocation 或 folder 判断
    return NO;
}

// 强制应用已记录的用户移动位置
static void ApplyUserMovedLocations(SBIconListModel *model) {
    if (!model || IsDockList(model)) return;

    NSString *listID = [model uniqueIdentifier];
    if (!listID.length) return;

    LoadGridConfig();

    [gConfigLock lock];
    NSDictionary *listConfig = [gGridConfig[listID] copy];
    [gConfigLock unlock];

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
        } else if ([model respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
            [model setFixedLocation:loc forIcon:icon];
        }
    }
}

static void CleanupIconFromPlist(SBIconListModel *model, id icon) {
    if (!model || !icon) return;
    NSString *listID = [model uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return;

    LoadGridConfig();
    [gConfigLock lock];
    NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy];
    if (listConfig && listConfig[iconID]) {
        [listConfig removeObjectForKey:iconID];
        if (listConfig.count == 0) {
            [gGridConfig removeObjectForKey:listID];
        } else {
            gGridConfig[listID] = listConfig;
        }
        [gConfigLock unlock];
        SaveGridConfig();
    } else {
        [gConfigLock unlock];
    }
}

// 用户真正移动时记录 + 立即 Apply
static void RecordUserMovedIcon(SBIconListModel *model, id icon, unsigned long long index) {
    if (!model || !icon || index == NSNotFound || index >= [model maxNumberOfIcons] || IsDockList(model)) return;

    NSString *listID = [model uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return;

    // 立即设为 Fixed
    if ([model respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
        [model setFixedLocation:index forIcon:icon options:0];
    } else if ([model respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [model setFixedLocation:index forIcon:icon];
    }

    // 写入内存 + 磁盘
    LoadGridConfig();
    [gConfigLock lock];
    NSMutableDictionary *listConfig = [gGridConfig[listID] mutableCopy] ?: [NSMutableDictionary new];
    listConfig[iconID] = @(index);
    gGridConfig[listID] = listConfig;
    [gConfigLock unlock];
    SaveGridConfig();

    // 强制重新 Apply 所有已记录图标（关键：防止 %orig 清空其他 fixed）
    ApplyUserMovedLocations(model);
}

// ===================================================================
// 视图层
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

- (void)layoutIconsNow {
    if ([self respondsToSelector:@selector(model)] && [self model]) {
        ApplyUserMovedLocations([self model]);
    }
    %orig;
}

- (void)setIconsNeedLayout {
    if ([self respondsToSelector:@selector(model)] && [self model]) {
        ApplyUserMovedLocations([self model]);
    }
    %orig;
}

%end

// ===================================================================
// Manager 层
// ===================================================================
%hook SBHIconManager

- (long long)listsFixedIconLocationBehavior {
    return 1;
}

- (long long)listsFixedIconLocationBehaviorForFolderClass:(Class)cls {
    return 1;
}

- (long long)iconModel:(id)model listsFixedIconLocationBehaviorForFolderClass:(Class)cls {
    return 1;
}

- (void)ensureFixedIconLocationsIfNecessary {
    // 空实现，防止系统强制重置
}

%end

// ===================================================================
// 数据层
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
    if (!listID || !iconID) return %orig;

    LoadGridConfig();
    [gConfigLock lock];
    NSDictionary *cfg = gGridConfig[listID];
    BOOL fixed = (cfg && cfg[iconID] != nil);
    [gConfigLock unlock];

    if (fixed) return YES;
    return %orig;
}

- (BOOL)isIconFixed:(id)icon gridCellInfoOptions:(unsigned long long)options {
    return [self isIconFixed:icon];
}

- (unsigned long long)fixedLocationForIcon:(id)icon {
    if (!icon || IsDockList(self)) return %orig;

    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    if (!listID || !iconID) return %orig;

    LoadGridConfig();
    [gConfigLock lock];
    NSDictionary *cfg = gGridConfig[listID];
    NSNumber *num = cfg ? cfg[iconID] : nil;
    [gConfigLock unlock];

    if (num) {
        unsigned long long loc = [num unsignedLongLongValue];
        if (loc < [self maxNumberOfIcons]) {
            // 强制写回内部 map
            if ([self respondsToSelector:@selector(setFixedLocation:forIcon:options:)]) {
                [self setFixedLocation:loc forIcon:icon options:0];
            } else if ([self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
                [self setFixedLocation:loc forIcon:icon];
            }
            return loc;
        }
    }
    return %orig;
}

- (void)removeAllFixedIconLocations {}
- (void)removeFixedIconLocationForIcon:(id)icon {}
- (void)removeFixedIconLocationsForIcons:(id)icons {}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfo:(id)info {}
- (void)removeFixedIconLocationsForIconsInGridRange:(struct SBHIconGridRange)range gridCellInfoOptions:(unsigned long long)options {}

- (id)_updateModelByRepairingGapsIfNecessary { return nil; }
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons { return nil; }
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoiding { return icons; }

- (BOOL)isGridLayoutValid { return YES; }
- (BOOL)isGridLayoutValid:(id)info { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options { return YES; }
- (BOOL)isGridLayoutValidWithOptions:(unsigned long long)options outOfBoundsIcons:(id *)outIcons {
    if (outIcons) *outIcons = nil;
    return YES;
}
- (BOOL)canUseFastGridLayoutValidity { return NO; }

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

// 用户真正落地的路径
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    RecordUserMovedIcon(self, icon, index);
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    RecordUserMovedIcon(self, icon, index);
    return result;
}

// 系统内部路径：不记录新位置，但强制 Apply 已有记录
- (id)insertIcon:(id)icon atIndex:(unsigned long long)index options:(unsigned long long)options {
    id result = %orig;
    ApplyUserMovedLocations(self);
    return result;
}

- (void)moveContainedIcon:(id)icon toIndex:(unsigned long long)index options:(unsigned long long)options {
    %orig;
    ApplyUserMovedLocations(self);
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
    id icon = nil;
    NSArray *icons = [self icons];
    if (icons && index < icons.count) {
        icon = icons[index];
    }
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}
- (void)removeIconAtIndex:(unsigned long long)index options:(unsigned long long)options {
    id icon = nil;
    NSArray *icons = [self icons];
    if (icons && index < icons.count) {
        icon = icons[index];
    }
    %orig;
    if (icon) CleanupIconFromPlist(self, icon);
}

- (void)setIcons:(NSArray *)icons {
    %orig;
    ApplyUserMovedLocations(self);
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options {
    id result = %orig;
    ApplyUserMovedLocations(self);
    return result;
}
- (id)setIcons:(id)icons gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutationOptions {
    id result = %orig;
    ApplyUserMovedLocations(self);
    return result;
}
- (id)setIconsFromIconListModel:(id)model {
    id result = %orig;
    ApplyUserMovedLocations(self);
    return result;
}

%end
