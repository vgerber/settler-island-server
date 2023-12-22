use std::{collections::HashMap, ops::Add};

use serde::de::value;

use super::base_resource::ResourcedId;

pub type ResourceCollection = HashMap<ResourcedId, usize>;

pub struct PlayerResources {
    resources: ResourceCollection,
}

impl PlayerResources {
    pub fn new() -> Self {
        PlayerResources {
            resources: HashMap::new(),
        }
    }

    pub fn get_resources(&self) -> ResourceCollection {
        self.resources.clone()
    }

    pub fn add_resource(&mut self, resource: &ResourcedId, count: &usize) {
        match self.resources.get(resource) {
            None => self.resources.insert(resource.clone(), *count),
            Some(resource_count) => self
                .resources
                .insert(resource.clone(), resource_count + count),
        };
    }

    pub fn add_resources(&mut self, added_resources: ResourceCollection) {
        added_resources
            .into_iter()
            .for_each(|(resource, count)| self.add_resource(&resource, &count))
    }

    pub fn remove_resource(&mut self, resource: &ResourcedId, count: &usize) -> bool {
        match self.resources.get(resource) {
            None => false,
            Some(resource_count) => {
                if resource_count < count {
                    return false;
                }
                self.resources
                    .insert(resource.clone(), resource_count - count)
                    .is_some()
            }
        }
    }

    pub fn remove_resources(&mut self, removed_resources: &ResourceCollection) -> bool {
        removed_resources
            .into_iter()
            .any(|(resource, count)| self.remove_resource(&resource, &count))
    }

    pub fn get_resource(&self, resource: &ResourcedId) -> Option<&usize> {
        self.resources.get(resource)
    }

    pub fn get_total_resources(&self) -> usize {
        get_total_resources(&self.resources)
    }

    pub fn has_resource(&self, resource: &ResourcedId, expected_count: &usize) -> bool {
        self.resources.get(resource).unwrap_or(&0) >= expected_count
    }

    pub fn has_resources(&self, checked_resources: &ResourceCollection) -> bool {
        checked_resources
            .into_iter()
            .all(|(resource, count)| self.has_resource(&resource, &count))
    }
}

pub fn get_total_resources(resource_collection: &ResourceCollection) -> usize {
    match resource_collection
        .values()
        .into_iter()
        .map(|value| *value)
        .reduce(|a, b| a + b)
    {
        None => 0,
        Some(sum) => sum,
    }
}
